# Лицензии и авторы словарей Twiga Switcher

Этот каталог относится к данным словарей и инструменту, из которого получены
базовые данные. Он не устанавливает лицензию собственного исходного кода
Twiga Switcher. Лицензия кода оформляется отдельно в корне репозитория.

Все файлы этого каталога включаются в ресурсный пакет приложения
`TwigaSwitcher_LayoutSwitcherLexicon.bundle/Contents/Resources/Licenses`.

## Базовые русские и английские словари

- Источник: [wordfreq 3.1.1](https://pypi.org/project/wordfreq/3.1.1/),
  Copyright 2022 Robyn Speer.
- Данные и производные индексы `Lexicons/Base`: [CC BY-SA 4.0](CC-BY-SA-4.0.txt).
- Уведомления об авторах и исходных корпусах: [wordfreq-NOTICE.md](wordfreq-NOTICE.md).
  Сохраняйте их при распространении словарей.
- Лицензия программного пакета wordfreq: [Apache 2.0](Apache-2.0.txt).
  Оригинальное уведомление `LICENSE.txt` из официального wheel сохранено
  без изменений как [wordfreq-LICENSE.txt](wordfreq-LICENSE.txt).
  Python-пакет используется для генерации данных и не включается в приложение.

Изменения данных в Twiga Switcher: выбраны русский и английский языки,
нормализованы регистр, Unicode, пробелы и кавычки, отфильтрованы записи,
частотные оценки преобразованы в целые числа с порогом 2500, данные
скомпилированы в двоичные индексы `.lsidx`. Это производные данные,
а не неизменённые исходные файлы wordfreq.

Воспроизведение выполняет `scripts/generate-base-lexicons.sh` из корня
репозитория. Версия и контрольная сумма источника записаны в
`Lexicons/Base/manifest.json`. SHA-256 официального wheel:

```text
4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473
```

## Computer Terms

- Авторы: Copyright (c) 2026 LayoutSwitcher contributors.
- Словарь терминов и его оценки: [CC0 1.0](CC0-1.0.txt).
- Уведомление: [computer-terms-NOTICE.txt](computer-terms-NOTICE.txt).
- Исходные записи находятся в `Dictionaries/Computer Terms.layoutdict/entries.tsv`
  в корне репозитория. Этот пакет содержит собственные `NOTICE.txt` и `LICENSE.txt`.
- Встроенные индексы находятся в `Lexicons/ComputerTerms`.

## Источники текстов лицензий

- Apache 2.0: <https://www.apache.org/licenses/LICENSE-2.0.txt>.
- CC BY-SA 4.0: <https://creativecommons.org/licenses/by-sa/4.0/legalcode>.
- CC0 1.0: <https://creativecommons.org/publicdomain/zero/1.0/legalcode>;
  локальная текстовая копия получена из
  <https://github.com/spdx/license-list-data/blob/main/text/CC0-1.0.txt>.

При распространении сохраняйте лицензии данных и уведомления об авторах
вместе с соответствующими словарями, в том числе внутри готового приложения.
