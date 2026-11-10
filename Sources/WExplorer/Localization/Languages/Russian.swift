extension Language {
    static let russian = Language(code: "ru", name: "Русский", strings: [
        // Общие кнопки и слова
        .ok: "ОК",
        .cancel: "Отмена",
        .yes: "Да",
        .yesToAll: "Да для всех",
        .no: "Нет",
        .close: "Закрыть",
        .later: "Позже",
        .cancelling: "Отмена...",
        .calculating: "Вычисление...",

        // Особые места
        .myComputer: "Мой компьютер",
        .desktop: "Рабочий стол",
        .myDocuments: "Мои документы",
        .homeFolder: "Домашняя папка",
        .searchResults: "Результаты поиска: {0}",

        // Типы объектов
        .typeFolder: "Папка с файлами",
        .typeFile: "Файл",
        .typeSystemFolder: "Системная папка",
        .diskLocal: "Локальный диск",
        .diskRemovable: "Съёмный диск",
        .diskNetwork: "Сетевой диск",
        .diskFree: "Свободно: {0} из {1}",

        // Единицы и форматы
        .unitBytes: "байт",
        .unitKB: "КБ",
        .unitMB: "МБ",
        .unitGB: "ГБ",
        .unitTB: "ТБ",
        .dateFormat: "dd.MM.yyyy H:mm",

        // Виды и колонки
        .viewThumbnails: "Эскизы страниц",
        .viewTiles: "Плитка",
        .viewIcons: "Значки",
        .viewList: "Список",
        .viewDetails: "Таблица",
        .columnName: "Имя",
        .columnSize: "Размер",
        .columnType: "Тип",
        .columnModified: "Изменён",
        .sortModified: "Дата изменения",

        // Заголовки меню
        .menuFile: "Файл",
        .menuEdit: "Правка",
        .menuView: "Вид",
        .menuFavorites: "Избранное",
        .menuTools: "Сервис",
        .menuHelp: "Справка",
        .menuGo: "Переход",
        .menuWindow: "Окно",

        // Меню «Файл»
        .newWindow: "Новое окно",
        .newFolder: "Создать папку",
        .newTextDocument: "Создать текстовый документ",
        .open: "Открыть",
        .openInNewWindow: "Открыть в новом окне",
        .showInFinder: "Показать в Finder",
        .delete: "Удалить",
        .rename: "Переименовать",
        .properties: "Свойства",

        // Меню «Правка»
        .undo: "Отменить",
        .redo: "Повторить",
        .cut: "Вырезать",
        .copy: "Копировать",
        .paste: "Вставить",
        .moveHere: "Переместить сюда",
        .copyPath: "Копировать путь",
        .copyToFolder: "Копировать в папку...",
        .moveToFolder: "Переместить в папку...",
        .selectAll: "Выделить все",
        .invertSelection: "Обратить выделение",
        .move: "Переместить",

        // Переход
        .back: "Назад",
        .forward: "Вперёд",
        .up: "Вверх",
        .upOneLevel: "На один уровень вверх",
        .goToFolder: "Перейти к папке...",

        // Меню «Вид»
        .explorerBar: "Панели обозревателя",
        .search: "Поиск",
        .folders: "Папки",
        .views: "Виды",
        .arrangeIcons: "Упорядочить значки",
        .hiddenFiles: "Скрытые файлы",
        .refresh: "Обновить",

        // Избранное
        .addToFavorites: "Добавить в избранное",
        .removeFromFavorites: "Удалить из избранного",
        .addedToFavorites: "Добавлено в избранное: {0}",

        // Сервис
        .openInTerminal: "Открыть в Терминале",
        .showHiddenFiles: "Показывать скрытые файлы",
        .systemSettings: "Системные настройки...",
        .language: "Язык",

        // Справка и меню приложения
        .keyboardShortcuts: "Сочетания клавиш",
        .shortcutsText: """
            Enter — открыть
            Backspace — на уровень вверх
            Cmd+[  /  Cmd+]  или  Option+←/→ — назад / вперёд
            Cmd+↑ — на уровень вверх,  Cmd+↓ — открыть
            Cmd+L — перейти к папке (адресная строка)

            Cmd+C / Cmd+X / Cmd+V — копировать / вырезать / вставить
            Cmd+Option+V — переместить сюда
            Cmd+Option+C — копировать путь
            Cmd+Backspace или Fn+Delete — в корзину
            F2 — переименовать
            Cmd+Shift+N — новая папка
            Cmd+Z / Cmd+Shift+Z — отменить / повторить
            Cmd+I — свойства

            Cmd+двойной щелчок, щелчок колёсиком — открыть папку в новом окне
            Cmd+щелчок в дереве или в «Других местах» — открыть в новом окне

            Cmd+1…5 — эскизы, плитка, значки, список, таблица
            Cmd+F — поиск,  Cmd+Option+F — дерево папок
            Cmd+Shift+. — скрытые файлы
            Cmd+R или F5 — обновить
            Cmd+N — новое окно
            """,
        .about: "О программе {0}",
        .hideApp: "Скрыть {0}",
        .hideOthers: "Скрыть остальные",
        .quitApp: "Выйти из {0}",
        .minimize: "Свернуть",
        .zoom: "Масштаб",
        .bringAllToFront: "Все окна — на передний план",

        // Контекстное меню «Создать»
        .create: "Создать",
        .createFolder: "Папку",
        .createTextDocument: "Текстовый документ",

        // Адресная строка
        .address: "Адрес",
        .go: "Переход",
        .placesList: "Список мест",

        // Панель задач
        .systemTasks: "Системные задачи",
        .viewSystemInfo: "Просмотр сведений о системе",
        .changeSettings: "Изменение параметров",
        .fileAndFolderTasks: "Задачи для файлов и папок",
        .otherPlaces: "Другие места",
        .details: "Подробно",
        .makeNewFolder: "Создать новую папку",
        .taskRenameFile: "Переименовать файл",
        .taskRenameFolder: "Переименовать папку",
        .taskMoveFile: "Переместить файл",
        .taskMoveFolder: "Переместить папку",
        .taskMoveItems: "Переместить выделенные объекты",
        .taskCopyFile: "Копировать файл",
        .taskCopyFolder: "Копировать папку",
        .taskCopyItems: "Копировать выделенные объекты",
        .taskDeleteFile: "Удалить файл",
        .taskDeleteFolder: "Удалить папку",
        .taskDeleteItems: "Удалить выделенные объекты",
        .modifiedAt: "Изменён: {0}",
        .sizeIs: "Размер: {0}",
        .totalSize: "Общий размер: {0}",
        .searchFor: "Поиск «{0}»",
        .searchIn: "В: {0}",

        // Строка состояния
        .objectsCount: "Объектов: {0}",
        .selectedCount: "Выделено объектов: {0}",
        .foundCount: "Найдено объектов: {0}",
        .freeSpace: " (Свободно на диске: {0})",
        .searching: "Поиск...",
        .noAccess: "Нет доступа",
        .cutStatus: "Вырезано объектов: {0}. Вставьте их в нужную папку (Cmd+V).",
        .copiedStatus: "Скопировано объектов: {0}.",
        .pathCopied: "Путь скопирован: {0}",
        .pathsCopied: "Скопировано путей: {0}",

        // Ошибки навигации
        .noAccessTitle: "Нет доступа к «{0}».",
        .noAccessFullDisk: "Отказано в доступе. Чтобы открыть эту папку, разрешите {0} полный доступ к диску: Системные настройки → Конфиденциальность и безопасность → Полный доступ к диску.",
        .cannotFind: "Не удаётся найти «{0}».",
        .checkSpelling: "Проверьте правильность написания и повторите попытку.",

        // Выбор папки для копирования/перемещения
        .chooseCopyDestination: "Выберите место, куда следует скопировать {0}, затем нажмите кнопку «{1}».",
        .chooseMoveDestination: "Выберите место, куда следует переместить {0}, затем нажмите кнопку «{1}».",
        .selectedItemsCount: "выделенные объекты ({0})",
        .quotedName: "«{0}»",

        // Подтверждения
        .confirmReplaceTitle: "Подтверждение замены",
        .confirmReplaceText: "Эта папка уже содержит объект с именем «{0}».\n\nЗаменить его? Существующий объект будет перемещён в корзину.",
        .confirmDeleteFileTitle: "Подтверждение удаления файла",
        .confirmDeleteFolderTitle: "Подтверждение удаления папки",
        .confirmDeleteOne: "Вы действительно хотите отправить «{0}» в корзину?",
        .confirmDeleteManyTitle: "Подтверждение удаления группы файлов",
        .confirmDeleteMany: "Вы действительно хотите отправить эти объекты ({0}) в корзину?",

        // Файловые операции
        .copying: "Копирование...",
        .moving: "Перемещение...",
        .progressFromTo: "Из «{0}» в «{1}»",
        .copyFailedSome: "Не удалось скопировать некоторые объекты",
        .moveFailedSome: "Не удалось переместить некоторые объекты",
        .cannotCopyItem: "Невозможно скопировать «{0}»",
        .cannotMoveItem: "Невозможно переместить «{0}»",
        .destinationInsideSource: "Конечная папка является вложенной для исходной папки.",
        .copyOfName: "Копия {0}",
        .copyOfNameNumbered: "Копия ({1}) {0}",
        .cannotMove: "Не удаётся переместить «{0}»",
        .cannotDelete: "Не удаётся удалить «{0}»",
        .invalidCharacters: "Имя файла не может содержать следующие знаки:",
        .cannotRename: "Не удаётся переименовать «{0}»",
        .nameExists: "Объект с именем «{0}» уже существует. Укажите другое имя.",
        .newFolderName: "Новая папка",
        .newFolderNameNumbered: "Новая папка ({0})",
        .cannotCreateFolder: "Не удаётся создать папку",
        .newTextDocumentName: "Новый текстовый документ",
        .newTextDocumentNameNumbered: "Новый текстовый документ ({0})",
        .cannotCreateTextDocument: "Не удаётся создать текстовый документ",
        .noWritePermission: "Возможно, нет прав на запись в эту папку.",

        // Архивы
        .archiveMenu: "Архив",
        .archiveExtract: "Распаковать",
        .archiveExtractEllipsis: "Распаковать...",
        .archiveExtractHere: "Распаковать здесь",
        .archiveExtractTo: "Распаковать в «{0}»",
        .archiveExtractToEach: "Распаковать каждый в свою папку",
        .archiveTest: "Тестировать",
        .archiveAddTo: "Добавить к «{0}»",
        .archiveChooseDestination: "Выберите папку, в которую следует распаковать {0}.",
        .archiveExtracting: "Распаковка...",
        .archiveTesting: "Проверка архива...",
        .archiveCompressing: "Сжатие...",
        .archiveTestPassed: "Ошибок не найдено",
        .archiveFailed: "Не удалось выполнить операцию с архивом",
        .archiveCannotRun: "Не удалось запустить архиватор.",
        .archiveEncryptionUnsupported: "Встроенный архиватор не поддерживает шифрование этого архива. Распаковать его можно через 7-Zip.",
        .archiveEnterPassword: "Введите пароль архива",
        .archiveWrongPassword: "Неверный пароль. Попробуйте ещё раз",
        .archiveAddDialog: "Добавить к архиву...",
        .archiveAddTitle: "Добавить к архиву",
        .archiveFieldArchive: "Архив:",
        .archiveFormatLabel: "Формат архива:",
        .archiveLevelLabel: "Уровень сжатия:",
        .archiveMethodLabel: "Метод сжатия:",
        .archiveDictionaryLabel: "Размер словаря:",
        .archiveWordLabel: "Размер слова:",
        .archiveSolidLabel: "Размер блока:",
        .archiveThreadsLabel: "Число потоков:",
        .archiveVolumesLabel: "Разбить на тома размером (в байтах):",
        .archiveParametersLabel: "Параметры:",
        .archiveUpdateLabel: "Режим изменения:",
        .archivePathModeLabel: "Режим путей:",
        .archiveOptionsGroup: "Опции",
        .archiveDeleteAfter: "Удалить файлы после сжатия (в корзину)",
        .archiveEncryptionGroup: "Шифрование",
        .archivePasswordLabel: "Введите пароль:",
        .archivePasswordRepeatLabel: "Повторите пароль:",
        .archiveShowPassword: "Показать пароль",
        .archiveEncryptionMethodLabel: "Метод шифрования:",
        .archiveEncryptNames: "Шифровать имена файлов",
        .archiveAuto: "Авто",
        .archiveLevelStore: "Без сжатия",
        .archiveLevelFastest: "Скоростной",
        .archiveLevelFast: "Быстрый",
        .archiveLevelNormal: "Нормальный",
        .archiveLevelMaximum: "Максимальный",
        .archiveLevelUltra: "Ультра",
        .archiveSolidOff: "Без блоков",
        .archiveSolidOn: "Непрерывный",
        .archiveUpdateAddReplace: "Добавить и заменить",
        .archiveUpdateAddUpdate: "Обновить и добавить",
        .archiveUpdateFreshen: "Обновить существующие",
        .archiveUpdateSync: "Синхронизировать",
        .archivePathRelative: "Относительные пути",
        .archivePathFull: "Полные пути",
        .archivePathAbsolute: "Абсолютные пути",
        .archiveBadDestination: "Неверное расположение архива",
        .archiveBadVolumeSize: "Неверный размер тома",
        .archivePasswordMismatch: "Пароли не совпадают",
        .archivePasswordASCII: "Пароль zip-архива может содержать только латинские буквы, цифры и знаки. Используйте такой пароль или формат 7z.",

        // Названия действий для «Отменить …»
        .actionCopy: "копирование",
        .actionMove: "перемещение",
        .actionDelete: "удаление",
        .actionRename: "переименование",
        .actionNewFolder: "создание папки",
        .actionNewDocument: "создание документа",

        // Переименование
        .renameTitle: "Переименование",
        .renamePrompt: "Новое имя для «{0}»:",

        // Свойства
        .propertiesTitle: "Свойства: {0}",
        .readOnly: "Только чтение",
        .hidden: "Скрытый",
        .propType: "Тип:",
        .propLocation: "Расположение:",
        .propSize: "Размер:",
        .propContains: "Содержит:",
        .propCreated: "Создан:",
        .propModified: "Изменён:",
        .propAttributes: "Атрибуты:",
        .filesAndFolders: "Файлов: {0}; папок: {1}",

        // Панель поиска
        .searchHeading: "Искать файлы и папки",
        .searchNamePrompt: "Часть имени файла или имя файла целиком:",
        .searchWhere: "Где искать:",
        .searchButton: "Найти",
        .searchScopeCurrent: "В текущей папке",
        .searchScopeHome: "В домашней папке",
        .searchScopeComputer: "На всём компьютере",

        // Смена языка
        .languageChangedTitle: "Язык интерфейса изменён",
        .languageChangedText: "Новый язык применится после перезапуска {0}.",
        .restartNow: "Перезапустить",
    ])
}
