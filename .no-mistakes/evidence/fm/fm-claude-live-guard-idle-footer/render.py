from pathlib import Path
from ansi2html import Ansi2HTMLConverter
root=Path('/home/denguinho/.no-mistakes/evidence/01M4DK7C9KE09JXBG0DQVT0PRS')
for file in root.glob('*.ansi'):
    file.with_suffix('.html').write_text(Ansi2HTMLConverter(dark_bg=True, title=file.stem+' — live Claude terminal').convert(file.read_text()))
