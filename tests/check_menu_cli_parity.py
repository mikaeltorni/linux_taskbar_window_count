"""Compare the public line menu with CLI component actions using isolated files."""
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def run_menu(environment, selected, removed):
    """Enter complete install/removal choices in a real terminal.

    Parameters: environment - isolated fixture variables; selected - first prompt bytes; removed - removal prompt bytes.
    Returns: process status and complete terminal output.
    """
    print(f'environment={environment!r} selected={selected!r} removed={removed!r}')
    master, slave = pty.openpty()
    process = subprocess.Popen(['bash',str(CHECKOUT/'install.sh')],env=environment,
                               stdin=slave,stdout=slave,stderr=slave,start_new_session=True)
    os.close(slave)
    output = bytearray()
    sent = False
    removal_sent = False
    deadline = time.monotonic()+20
    try:
        while time.monotonic() < deadline:
            if select.select([master],[],[],0.1)[0]:
                try:
                    chunk = os.read(master,65536)
                except OSError:
                    break
                if not chunk:
                    break
                output.extend(chunk)
                if not sent and b'IDs to install or reconfigure' in output:
                    os.write(master,selected)
                    sent = True
                if not removal_sent and b'IDs to uninstall' in output:
                    os.write(master,removed)
                    removal_sent = True
            elif process.poll() is not None:
                break
        if process.poll() is None:
            process.wait(timeout=2)
        assert sent,output.decode(errors='replace')
        result = process.returncode,output.decode(errors='replace')
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
    print(result)
    return result


with tempfile.TemporaryDirectory(prefix='badges-menu-parity-') as directory:
    temporary = Path(directory)
    CHECKOUT = temporary/'repo'
    CHECKOUT.mkdir()
    for name in ('lib','installer','installation_configs','workspace-window-count@local'):
        shutil.copytree(ROOT/name,CHECKOUT/name)
    shutil.copy2(ROOT/'install.sh',CHECKOUT/'install.sh')
    tools = temporary/'tools'
    tools.mkdir()
    (tools/'getent').write_text('#!/bin/bash\nprintf "%s:x:%s:%s::%s:/bin/bash\\n" "$USER" "$(id -u)" "$(id -g)" "$HOME"\n')
    (tools/'gsettings').write_text('''#!/bin/bash
if [[ ${1:-} == --schemadir ]]; then shift 2; fi
if [[ ${1:-} == get ]]; then printf "['existing@local']\\n"; exit 0; fi
printf '%s\\t' "$@" >> "$EFFECTS"
printf '\\n' >> "$EFFECTS"
''')
    (tools/'glib-compile-schemas').write_text('#!/bin/bash\nprintf "compile\\n" >> "$EFFECTS"\n')
    for tool in tools.iterdir():
        tool.chmod(0o755)
    cases = []
    for name in ('cli','menu','cancel'):
        home = temporary/name
        home.mkdir()
        sentinel = home/'.config/personal-settings'
        sentinel.parent.mkdir()
        sentinel.write_text('user configuration stays')
        effects = temporary/(name+'-effects')
        effects.touch()
        env = dict(PATH=str(tools)+':/usr/local/bin:/usr/bin:/bin',HOME=str(home),USER=os.environ.get('USER','mk'),
                   XDG_STATE_HOME=str(home/'state'), XDG_CONFIG_HOME=str(home/'.config'),
                   XDG_CACHE_HOME=str(home/'cache'), EFFECTS=str(effects),TERM='xterm',
                   WWC_BIN=str(ROOT/'dist/wwc-tools'), WWC_BADGE_POSITION='top-right',WWC_COUNT_THRESHOLD='2')
        cases.append((home,effects,env))
    cli,menu,cancel = cases
    result = subprocess.run(['bash',str(CHECKOUT/'install.sh'),'--select','badge_position,count_threshold'],env=cli[2],text=True,capture_output=True)
    assert result.returncode == 0,(result.stdout,result.stderr)
    status,output = run_menu(menu[2],b'badge_position,count_threshold\r',b'\r')
    assert status == 0,output
    assert cli[1].read_bytes() == menu[1].read_bytes(),(cli[1].read_text(),menu[1].read_text())
    assert 'badge-position' in cli[1].read_text() and 'count-threshold' in cli[1].read_text()
    for home,effects,env in cases[:2]:
        extension = home/'.local/share/gnome-shell/extensions/workspace-window-count@local/extension.js'
        assert extension.read_bytes() == (ROOT/'workspace-window-count@local/extension.js').read_bytes()
        assert (home/'.config/personal-settings').read_text() == 'user configuration stays'
        effects.write_text('')
    result = subprocess.run(['bash',str(CHECKOUT/'install.sh'),'--uninstall','badge_position'],env=cli[2],text=True,capture_output=True)
    assert result.returncode == 0,(result.stdout,result.stderr)
    status,output = run_menu(menu[2],b'-\r',b'badge_position\r')
    assert status == 0,output
    assert cli[1].read_bytes() == menu[1].read_bytes(),(cli[1].read_text(),menu[1].read_text())
    assert 'compile' not in menu[1].read_text(),'removal-only menu redeployed core files'
    for home,effects,env in cases[:2]:
        result = subprocess.run(['bash',str(CHECKOUT/'install.sh'),'--detect'],env=env,text=True,capture_output=True)
        assert result.returncode == 0,(result.stdout,result.stderr)
        assert set(result.stdout.splitlines()) == {'badge_position\tabsent','count_threshold\tinstalled','workspace_scope\tabsent','badge_appearance\tabsent'},result.stdout
        assert (home/'.config/personal-settings').read_text() == 'user configuration stays'
    status,output = run_menu(cancel[2],b'q\r',b'\r')
    assert status == 0 and not cancel[1].read_text(),output
    assert not (cancel[0]/'.local/share/gnome-shell/extensions').exists()
print('PASS: identical menu/CLI install and removal effects, unchanged config, cancellation and no core redeploy for removal')
