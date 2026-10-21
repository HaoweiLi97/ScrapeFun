import os
import pathlib
import re
import json
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = (ROOT / 'scripts/one-click-compose-deploy.sh').read_text()

def functions(*names):
    return '\n'.join(re.search(r'^' + name + r'\(\) \{.*?^\}', SOURCE, re.M | re.S)[0] for name in names)

class GpuDeploymentTests(unittest.TestCase):
    def bash(self, code):
        return subprocess.run(['bash'], input='set -euo pipefail\n' + code, text=True, capture_output=True)

    def test_wsl_takes_precedence_over_nvidia_toolkit(self):
        code = functions('resolve_auto_gpu_mode') + '''
host_has_wsl_gpu() { return 0; }
host_has_nvidia_gpu() { echo 'should not query NVIDIA Toolkit' >&2; return 1; }
resolve_auto_gpu_mode
[[ "$SCRAPEFUN_GPU_MODE" == wsl ]]
'''
        result = self.bash(code)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rendered_wsl_settings_survive_in_the_primary_compose_file(self):
        with tempfile.TemporaryDirectory() as temp:
            target = pathlib.Path(temp) / 'docker-compose.remote.yml'
            target.write_text((ROOT / 'docker-compose.remote.yml').read_text())
            code = functions('create_deploy_tmp_file', 'replace_file_if_changed', 'render_compose_with_gpu_mode') + f'''
COMPOSE_TARGET='{target}'
SCRAPEFUN_GPU_MODE=wsl
SCRAPEFUN_WSL_VULKAN_PREFIX=/opt/test-mesa
SCRAPEFUN_WSL_GPU_ADAPTER=NVIDIA
render_compose_with_gpu_mode
'''
            result = self.bash(code)
            self.assertEqual(result.returncode, 0, result.stderr)
            rendered = target.read_text()
            self.assertIn('/dev/dxg:/dev/dxg', rendered)
            self.assertIn('/opt/test-mesa:/opt/test-mesa:ro', rendered)
            self.assertIn('IMAGE_UPSCALE_GPU_FALLBACK_POLICY=strict', rendered)
            self.assertNotIn('gpus: all', rendered)
            self.assertNotIn('__APP_GPU_', rendered)

    def test_old_template_is_rejected_instead_of_losing_gpu_environment(self):
        with tempfile.TemporaryDirectory() as temp:
            target = pathlib.Path(temp) / 'old.yml'
            target.write_text('services:\n  app:\n    # __APP_GPU_BLOCK__\n')
            code = functions('create_deploy_tmp_file', 'replace_file_if_changed', 'render_compose_with_gpu_mode') + f'''
COMPOSE_TARGET='{target}'
SCRAPEFUN_GPU_MODE=wsl
RED='' NC=''
render_compose_with_gpu_mode
'''
            result = self.bash(code)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('/dev/dxg', target.read_text())

    def test_saved_wsl_driver_and_adapter_are_reused(self):
        with tempfile.TemporaryDirectory() as temp:
            env = pathlib.Path(temp) / 'saved.env'
            env.write_text('SCRAPEFUN_WSL_VULKAN_PREFIX=/opt/custom-mesa\nSCRAPEFUN_WSL_GPU_ADAPTER=AMD\n')
            code = functions('read_env_value', 'load_saved_gpu_settings') + f'''
UPDATER_ENV_FILE='{env}'
SCRAPEFUN_WSL_VULKAN_PREFIX='' SCRAPEFUN_WSL_GPU_ADAPTER='' SCRAPEFUN_DRI_DEVICE=''
NVIDIA_VISIBLE_DEVICES_WAS_SET='' NVIDIA_DRIVER_CAPABILITIES_WAS_SET=''
load_saved_gpu_settings
[[ "$SCRAPEFUN_WSL_VULKAN_PREFIX" == /opt/custom-mesa && "$SCRAPEFUN_WSL_GPU_ADAPTER" == AMD ]]
'''
            result = self.bash(code)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_cpu_mode_does_not_install_gpu_packages(self):
        with tempfile.TemporaryDirectory() as temp:
            result = subprocess.run(['bash', str(ROOT/'scripts/ensure-comic-gpu-environment.sh'), 'none', 'docker', temp], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(list(pathlib.Path(temp).iterdir()), [])

    def test_native_release_accepts_published_combined_checksums(self):
        source = (ROOT/'scripts/one-click-native-deploy.sh').read_text()
        selector = re.search(r'python3 - "\$stage/releases.json".*?<<\x27PY\x27\n(.*?)\nPY', source, re.S)[1]
        verifier = re.search(r'python3 - "\$stage/checksums".*?<<\x27PY\x27\n(.*?)\nPY', source, re.S)[1]
        with tempfile.TemporaryDirectory() as temp:
            name='scrapefun-server-linux-amd64-0.4.0-stable.tar.gz'
            releases=pathlib.Path(temp)/'releases.json'
            releases.write_text(json.dumps({'assets':[{'name':n,'browser_download_url':'https://example.test/'+n} for n in [name,'SHA256SUMS']]}))
            selected=subprocess.run(['python3','-c',selector,str(releases),'stable'],text=True,capture_output=True)
            self.assertEqual(selected.returncode,0,selected.stderr)
            self.assertEqual(selected.stdout.splitlines()[-1],name)
            sums=pathlib.Path(temp)/'SHA256SUMS'
            sums.write_text('b'*64+'  other.tar.gz\n'+'a'*64+'  '+name+'\n')
            verified=subprocess.run(['python3','-c',verifier,str(sums),name],text=True,capture_output=True)
            self.assertEqual(verified.returncode,0,verified.stderr)
            self.assertEqual(verified.stdout.strip(),'a'*64)
            rejected=subprocess.run(['python3','-c',verifier,str(sums),'absent.tar.gz'],text=True,capture_output=True)
            self.assertNotEqual(rejected.returncode,0)

if __name__ == '__main__':
    unittest.main()
