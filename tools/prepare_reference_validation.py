"""Create a separate validation app using independently computed reference fixtures.

Does not modify the original application, its desktop golden, or model weights.
"""
import hashlib
import json
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    report_path = ROOT.parent / 'CNN-Tutorial/artifacts/v0.5-backend-audit/report.json'
    report = json.loads(report_path.read_text())
    if not report['default_reproduces_original_all_outputs'] or report['samples'] != 372:
        raise RuntimeError('Desktop baseline reproduction was not verified')
    if report['model_sha256'] != '7891518a9b70ec6b3be8649123651780ce87ede1e69a9a49c394c17d203a0baa':
        raise RuntimeError('Unexpected model')
    standalone = ROOT / 'artifacts/evsoc-system-r1/embedded_sw/SapphireSoc/software/standalone'
    original = standalone / 'evsoc_tinyml_gesture'
    output = standalone / 'evsoc_tinyml_gesture_reference'
    shutil.copytree(original, output, ignore=shutil.ignore_patterns('build', '.git'))
    data = output / 'src/cnn_gesture_data.cc'
    text = data.read_text()
    baseline_manifest = json.loads((ROOT.parent / 'CNN-Tutorial/artifacts/v0.3-int8/golden/manifest.json').read_text())
    for index, vector in enumerate(report['reference_vectors']):
        if vector['input_sha256'] != baseline_manifest['vectors'][index]['input_sha256']:
            raise RuntimeError('Input fixture mismatch')
        pattern = rf'(const int8_t cnn_golden_{index}_output\[3\] = \{{).*?(\}};)'
        value = ', '.join(str(v) for v in vector['output_int8'])
        text, count = re.subn(pattern, lambda m: m[1]+'\n  '+value+'\n'+m[2], text, flags=re.S)
        if count != 1:
            raise RuntimeError('Expected exactly one output fixture')
    data.write_text('// Validation backend: TensorFlow 2.15.1 BUILTIN_REF; see reference_validation.json.\n'+text)
    evidence = dict(reference_report_sha256=sha(report_path), reference_report=report,
                    original_application=str(original), derived_application=str(output),
                    original_data_sha256=sha(original/'src/cnn_gesture_data.cc'),
                    reference_data_sha256=sha(data), model_array_sha256=sha(output/'src/model/gesture_int8_model_data.cc'),
                    note='Only expected output fixtures changed; input/model/runtime and strict comparison retained.')
    (output/'reference_validation.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(str(output))

if __name__ == '__main__':
    main()
