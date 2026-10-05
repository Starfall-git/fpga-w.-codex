"""Prepare an isolated power-on-reset experiment using the existing r1 ELF.

Keep memory admission under the original AI/DDR reset policy, but let the
official Sapphire debug domain leave reset even while DDR is not admitted.
This is a diagnostic candidate, not a board-verified fix.
"""
from pathlib import Path
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'artifacts/evsoc-system-r1'
TARGET = ROOT / 'artifacts/evsoc-debug-reset-r2'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if TARGET.exists():
        raise FileExistsError('Do not overwrite a diagnostic build: ' + str(TARGET))
    TARGET.mkdir()
    skip = shutil.ignore_patterns('work', 'work_syn', 'work_pnr', 'work_pt',
                                 'outflow', 'ooc', '__pycache__', '*.log')
    for name in ('src', 'ip', 'official_source'):
        shutil.copytree(SOURCE / name, TARGET / name, ignore=skip)
    for name in ('example_top.v', 'Ti60_AR0135.xml', 'Ti60_AR0135.peri.xml',
                 'Ti60_AR0135.pt.sdc'):
        shutil.copy2(SOURCE / name, TARGET / name)
    wrapper = TARGET / 'src/cnn/cnn_soc_subsystem.v'
    before = wrapper.read_text(encoding='utf-8')
    old = '.io_asyncReset(ai_reset)'
    if before.count(old) != 1:
        raise ValueError('Unexpected Sapphire reset wiring')
    # uart_rst_n is the global rstn_sys of this candidate, with no AI feedback.
    wrapper.write_text(before.replace(old, '.io_asyncReset(!uart_rst_n)'), encoding='utf-8')
    top = TARGET / 'example_top.v'
    text = top.read_text(encoding='utf-8')
    old = '{w_ddr3_cal_pass, w_ddr3_cal_done, cam_pll_lock, sys_pll_lock} : w_axi_tp[3:0];'
    if text.count(old) != 1:
        raise ValueError('Unexpected LED wiring')
    text = text.replace(old,
        '{w_ddr3_cal_pass, w_ddr3_cal_done, cnn_ai_reset, cnn_hardware_ready} : w_axi_tp[3:0];')
    top.write_text(text, encoding='utf-8')
    elf = SOURCE / 'embedded_sw/SapphireSoc/software/standalone/evsoc_tinyml_gesture/build/evsoc_tinyml_gesture.elf'
    report = {
        'source': str(SOURCE), 'candidate': str(TARGET),
        'hypothesis': 'AI external-reset admission may hold the entire Sapphire debug domain in reset.',
        'change': 'Only Sapphire io_asyncReset follows global rstn_sys. AI transaction admission/abort remains unchanged.',
        'led_signals': {'led_o[0]': 'cnn_hardware_ready', 'led_o[1]': 'cnn_ai_reset',
                        'led_o[2]': 'w_ddr3_cal_done', 'led_o[3]': 'w_ddr3_cal_pass'},
        'unchanged_elf_sha256': sha(elf),
        'source_wrapper_sha256': sha(SOURCE / 'src/cnn/cnn_soc_subsystem.v'),
        'candidate_wrapper_sha256': sha(wrapper),
        'source_top_sha256': sha(SOURCE / 'example_top.v'),
        'candidate_top_sha256': sha(top),
        'same_project_xml': sha(SOURCE / 'Ti60_AR0135.xml') == sha(TARGET / 'Ti60_AR0135.xml'),
        'board_verified': False,
    }
    (TARGET / 'reset_experiment.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(TARGET)


if __name__ == '__main__':
    main()
