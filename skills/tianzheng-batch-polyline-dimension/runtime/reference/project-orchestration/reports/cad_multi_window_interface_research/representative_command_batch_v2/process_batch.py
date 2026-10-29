"""Run the frozen functional artifact adapter, without regenerating prefix."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).resolve().parent.parent / 'representative_command_batch_v1' / 'process_batch.py'), run_name='__main__')
