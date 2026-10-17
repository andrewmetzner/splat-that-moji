# Credits

Splat That Moji is built on other people's work. This page credits all of it.

## Inspiration

**[Splatmoji](https://github.com/cspeterson/splatmoji)** by Christopher Peterson
([@cspeterson](https://github.com/cspeterson)) supplied the idea: a hotkey, a searchable pop-up list, and copy/type/paste
insertion. The custom kaomoji file format here is deliberately the same as Splatmoji's, so its data files work as-is.
Splat That Moji is a separate macOS implementation and contains no Splatmoji code.

## Kaomoji data

The database (`Resources/kaomoji.tsv`) is merged from the datasets below. The counts are how many unique kaomoji each
one added, after the ones before it. Every source is pinned to a commit in [`tools/build_db.py`](tools/build_db.py).

| Dataset | Author | Added | License |
| --- | --- | ---: | --- |
| [emoticon-data](https://github.com/w33ble/emoticon-data) | Joe Fleming ([@w33ble](https://github.com/w33ble)) | 1,519 | MIT |
| [asciilib](https://github.com/iansinnott/asciilib) | Ian Sinnott ([@iansinnott](https://github.com/iansinnott)) | 248 | MIT |
| [kaomoji-collection](https://github.com/kaomojiya-collection/kaomoji-collection) | Kaomojiya ([kaomojiya.org](https://www.kaomojiya.org)) | 35,127 | MIT |
| [emoticon_kaomoji_dataset](https://github.com/ekohrt/emoticon_kaomoji_dataset) | [@ekohrt](https://github.com/ekohrt) | 57,557 | **None stated** |

**emoticon-data** contains about 1,500 kaomoji with English tags. It's the same set Splatmoji and
[rofimoji](https://github.com/fdw/rofimoji) ship, and the base the rest of the database was built on.

**asciilib** gave many well-known faces their names and keywords.

**kaomoji-collection** has about 41,000 kaomoji in 535 categories, curated by the Japanese kaomoji site
[顔文字屋 kaomojiya.org](https://www.kaomojiya.org). Its category names are romanized Japanese. The English keywords
attached to them in [`tools/kaomojiya_categories.tsv`](tools/kaomojiya_categories.tsv) were written for this project.

**emoticon_kaomoji_dataset** has about 62,000 kaomoji with tags. Its author collected them from these sites and then
hand-labeled about 52,000 entries:
[textemoticons.top](https://www.textemoticons.top/),
[messletters.com](https://www.messletters.com/en/emoticons/),
[kaomojis.org](https://kaomojis.org/),
[jref.com](https://jref.com/articles/emoji.36/),
[emoticonstext.com](https://www.emoticonstext.com/),
[Wikipedia's List of emoticons](https://en.wikipedia.org/wiki/List_of_emoticons),
[slangit.com](https://slangit.com/emoticons/kaomoji),
[a WikiLeaks-published emoticon page](https://wikileaks.org/ciav7p1/cms/page_17760284.html),
[emojicons.com](http://www.emojicons.com/popular),
[fastemoji.com](https://www.fastemoji.com/) and
[toolcalculator.com](https://www.toolcalculator.com/japanese-smiley-face.html).
The dataset has no license file, so it's included here with credit but without explicit permission. **@ekohrt, if you'd
like it removed or credited differently, please [open an issue](https://github.com/andrewmetzner/splat-that-moji/issues) and I'll fix it right away.**

Most kaomoji are folk art from Japanese and global internet culture, from 2channel to Tumblr to Discord, and their
original creators are unknown. Thanks to all of them too. (◕‿◕✿)

### What this project added

Everything else in the database was written for this project:
- a short hand-picked list of classics with their common names ([`tools/curated.tsv`](tools/curated.tsv));
- English keywords for kaomojiya's categories;
- the synonym table;
- the 39 browse categories;
- the cleanup rules: dropping emoji, Western emoticons, multi-line art, spam, and duplicates;
- the popularity scoring.

## License notices

The MIT License requires its copyright and permission notice to be included with copies of the data.

### emoticon-data

```
The MIT License (MIT)

Copyright (c) 2014 Joe Fleming

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### asciilib

```
MIT License

Copyright (c) 2022 Ian Sinnott

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### kaomoji-collection

```
MIT License

Copyright (c) 2026 Kaomojiya (https://www.kaomojiya.org)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
