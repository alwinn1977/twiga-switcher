enum MixedTypingCorpus {
    static let expected = """
    компьютер запускает Linux, затем browser показывает страницу проекта.
    Редактор открывает Node.js, меню показывает logs, пока editor сохраняет файл.
    Разработчик пишет TypeScript, люди читают русский комментарий.
    Сервис Docker запускает PostgreSQL, бюджет проекта остается прежним.
    Кластер Kubernetes запускает pod, любой разработчик видит статус.
    Новый API возвращает JSON, ключ защищает ответ клиента.
    Запрос HTTP приходит в backend, мьютекс защищает общий журнал.
    Система macOS запускает SwiftUI, плюс проверяет layout после слова.
    Команда Git создает commit, потом reviewer читает diff.
    Проверка CI запускает tests, когда изменился исходный код.
    Файл README описывает setup, русский текст уточняет шаги.
    Старый C++ модуль вызывает library, возвращает число.
    Платформа .NET собирает build, пользователь смотрит прогресс.
    Адрес localhost открывает dashboard, показывает новые данные.
    Редактор TextEdit печатает привет, затем hello, потом снова привет.
    Страница browser показывает Linux, содержит документацию.
    Значение timeout защищает request, когда сеть отвечает медленно.
    Модель machine learning изучает данные, однако не хранит ввод.
    После update приложение читает config, обновляет словарь.
    Параметр cache ускоряет lookup, память остается стабильной.
    Меню terminal показывает error, разработчик открывает report.
    Ключ API защищает request, когда сеть отвечает медленно.
    Второй компьютер проверяет Windows, затем запускает Linux.
    Финальная строка содержит Node.js, компьютер, English words.
    """ + "\n"

    static let expectedLines = expected.split(separator: "\n").map(String.init)

    static let expectedLinePrefixes: [String] = {
        var prefix = ""
        return expectedLines.map { line in
            prefix += line + "\n"
            return prefix
        }
    }()
}
