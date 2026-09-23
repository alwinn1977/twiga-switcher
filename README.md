# LayoutSwitcher

Нативное menu-bar приложение для macOS, которое автоматически исправляет слова и фразы, набранные в неверной русской или английской раскладке. Распознавание работает локально по частотным словарям в read-only `mmap`, поэтому не обращается к сети или диску на каждое нажатие.

## Требования

- macOS 14 или новее.
- Xcode и Xcode Command Line Tools.
- Включённые системные источники ввода US и Russian.

## Сборка и тесты

```bash
swift test
scripts/build-app.sh
open build/LayoutSwitcher.app
```

После первого запуска разрешите приложению доступ в разделах **System Settings → Privacy & Security → Accessibility** и **Input Monitoring**, затем завершите и снова откройте приложение. В строке меню появится значок клавиатуры. Пункты **Dictionaries…**, **Rules…** и **Shortcuts & Sound…** открывают нативные окна управления.

## Проверка

В обычном редактируемом поле:

- `ghbdtn ` автоматически заменяется на `привет `, после чего выбирается русская раскладка;
- `руддщ ` автоматически заменяется на `hello `, после чего выбирается английская раскладка;
- `Node.js`, `.NET`, `C++`, `machine learning`, `машинное обучение` и другие термины распознаются встроенным словарём Computer Terms;
- неоднозначное корректное слово остаётся без изменений.

Проверка рассчитана на TextEdit, Notes, обычные поля Safari/Chrome, Codex и Visual Studio Code. Приложение намеренно не работает в Terminal/iTerm, SSH/удалённых рабочих столах и secure password fields. Если Accessibility API не может надёжно подтвердить безопасность поля, исправление пропускается.

## Словари

Базовые английский и русский частотные словари всегда включены. Встроенный Computer Terms включён по умолчанию и может быть отключён без перезапуска. Собственный пакет импортируется через **Dictionaries… → Import…** и представляет собой директорию с расширением `.layoutdict`:

```text
My Terms.layoutdict/
  manifest.json
  entries.tsv
  NOTICE.txt       # необязательно
```

Минимальный `manifest.json`:

```json
{
  "schemaVersion": 1,
  "identifier": "com.example.my-terms",
  "name": "My Terms",
  "version": "1.0.0",
  "description": "Project vocabulary",
  "attribution": { "source": "My team", "license": "Proprietary" }
}
```

`entries.tsv` содержит `язык<TAB>оценка 0...8000<TAB>термин`; поддерживаются `en`, `ru`, пунктуация и фразы до восьми слов:

```tsv
en	4800	Node.js
en	4600	continuous delivery
ru	4700	база данных
```

Импорт ограничен 50 МиБ, 1 000 000 записей и 4 КиБ на строку. Пакет сначала полностью проверяется и компилируется, после чего каталог заменяется атомарно. Файлы хранятся в `~/Library/Application Support/LayoutSwitcher/Dictionaries`.

## Локальное обучение

По умолчанию **Control-Option-Z** отменяет последнее исправление в течение десяти секунд и запоминает для этой пары правило `never`. Обычный **Command-Z** остаётся командой текущего редактора. **Control-Option-L** принудительно исправляет текущее слово либо слово сразу после пробела и переключает раскладку для дальнейшего ввода. Оба сочетания можно изменить в **Shortcuts & Sound…**: выбрать модификаторы и физическую клавишу. Одинаковые сочетания для двух операций не допускаются.

Только после принудительного исправления меню предлагает **Always correct…** и **Never correct…** для соответствующей пары. Правила можно удалить в окне **Rules…**. После успешной смены раскладки звучит системный сигнал; в **Shortcuts & Sound…** его можно отключить.

На диске сохраняются только нормализованные пары `исходное → исправленное` и действие `always`/`never` в `~/Library/Application Support/LayoutSwitcher/rules.json`. Окружающий текст, история набора и содержимое полей не сохраняются.

## Данные, воспроизводимость и скорость

Базовые данные получены из закреплённого официального wheel `wordfreq 3.1.1` с проверкой SHA-256. Уведомления Apache-2.0 / CC BY-SA 4.0 находятся в ресурсах приложения. Computer Terms составлен специально для проекта и распространяется под CC0-1.0; исходный TSV доступен в `Dictionaries/Computer Terms.layoutdict`.

```bash
# Воспроизвести базовые индексы (создаёт изолированное Python-окружение)
scripts/generate-base-lexicons.sh

# Пересобрать встроенный предметный индекс
swift run LexiconCompiler compile-tsv \
  --input "Dictionaries/Computer Terms.layoutdict/entries.tsv" \
  --output-directory Sources/LayoutSwitcherLexicon/Resources/Lexicons/ComputerTerms \
  --manifest Sources/LayoutSwitcherLexicon/Resources/Lexicons/ComputerTerms/manifest.json \
  --source-name dev.layoutswitcher.dictionary.computer-terms \
  --source-version 1.0.0 --source-sha256 project-authored \
  --license CC0-1.0 --minimum-score 0 --subject-terms

# 10 000 прогретых mmap-поисков; бюджет 250 мс
scripts/benchmark-lexicons.sh
```

## Приватность и ограничения

Текущий буфер (не более восьми слов и 128 Unicode-скаляров) живёт только в памяти, очищается на границах безопасности и не записывается в файлы, журналы или сеть. Все словари и правила локальны. Сборочный скрипт применяет локальную ad-hoc подпись; для публичного распространения потребуется Developer ID и нотариализация.

Для отладки разрешение Accessibility можно сбросить командой ниже. Она отзывает уже выданный доступ, поэтому после неё разрешение потребуется предоставить заново:

```bash
tccutil reset Accessibility dev.layoutswitcher.prototype
```
