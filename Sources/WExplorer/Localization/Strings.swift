/// Ключи всех строк интерфейса. Тексты — в Localization/Languages/<язык>.swift.
/// Подстановки в текстах: {0}, {1}… по порядку аргументов tr(.key, a, b).
enum Str: String, CaseIterable {
    // Общие кнопки и слова
    case ok, cancel, yes, yesToAll, no, close, later
    case cancelling, calculating

    // Особые места
    case myComputer, desktop, myDocuments, homeFolder, searchResults

    // Типы объектов
    case typeFolder, typeFile, typeSystemFolder
    case diskLocal, diskRemovable, diskNetwork, diskFree

    // Единицы и форматы
    case unitBytes, unitKB, unitMB, unitGB, unitTB
    case dateFormat

    // Виды и колонки
    case viewThumbnails, viewTiles, viewIcons, viewList, viewDetails
    case columnName, columnSize, columnType, columnModified, sortModified

    // Заголовки меню
    case menuFile, menuEdit, menuView, menuFavorites, menuTools, menuHelp, menuGo, menuWindow

    // Меню «Файл»
    case newWindow, newFolder, newTextDocument, open, openInNewWindow, showInFinder
    case delete, rename, properties

    // Меню «Правка»
    case undo, redo, cut, copy, paste, moveHere, copyPath, copyToFolder, moveToFolder
    case selectAll, invertSelection, move

    // Переход
    case back, forward, up, upOneLevel, goToFolder

    // Меню «Вид»
    case explorerBar, search, folders, views, arrangeIcons, hiddenFiles, refresh

    // Избранное
    case addToFavorites, removeFromFavorites, addedToFavorites

    // Сервис
    case openInTerminal, showHiddenFiles, systemSettings, language

    // Справка и меню приложения
    case keyboardShortcuts, shortcutsText, about, hideApp, hideOthers, quitApp
    case minimize, zoom, bringAllToFront

    // Контекстное меню «Создать»
    case create, createFolder, createTextDocument

    // Адресная строка
    case address, go, placesList

    // Панель задач
    case systemTasks, viewSystemInfo, changeSettings
    case fileAndFolderTasks, otherPlaces, details, makeNewFolder
    case taskRenameFile, taskRenameFolder
    case taskMoveFile, taskMoveFolder, taskMoveItems
    case taskCopyFile, taskCopyFolder, taskCopyItems
    case taskDeleteFile, taskDeleteFolder, taskDeleteItems
    case modifiedAt, sizeIs, totalSize, searchFor, searchIn

    // Строка состояния
    case objectsCount, selectedCount, foundCount, freeSpace, searching, noAccess
    case cutStatus, copiedStatus, pathCopied, pathsCopied

    // Ошибки навигации
    case noAccessTitle, noAccessFullDisk, cannotFind, checkSpelling

    // Выбор папки для копирования/перемещения
    case chooseCopyDestination, chooseMoveDestination, selectedItemsCount, quotedName

    // Подтверждения
    case confirmReplaceTitle, confirmReplaceText
    case confirmDeleteFileTitle, confirmDeleteFolderTitle, confirmDeleteOne
    case confirmDeleteManyTitle, confirmDeleteMany

    // Файловые операции
    case copying, moving, progressFromTo
    case copyFailedSome, moveFailedSome, cannotCopyItem, cannotMoveItem, destinationInsideSource
    case copyOfName, copyOfNameNumbered
    case cannotMove, cannotDelete, invalidCharacters, cannotRename, nameExists
    case newFolderName, newFolderNameNumbered, cannotCreateFolder
    case newTextDocumentName, newTextDocumentNameNumbered, cannotCreateTextDocument, noWritePermission

    // Архивы
    case archiveMenu, archiveExtract, archiveExtractEllipsis, archiveExtractHere, archiveExtractTo, archiveExtractToEach
    case archiveTest, archiveAddTo, archiveChooseDestination
    case archiveExtracting, archiveTesting, archiveCompressing
    case archiveTestPassed, archiveFailed, archiveCannotRun, archiveEncryptionUnsupported
    case archiveEnterPassword, archiveWrongPassword
    case archiveAddDialog, archiveAddTitle, archiveFieldArchive, archiveFormatLabel, archiveLevelLabel, archiveMethodLabel
    case archiveDictionaryLabel, archiveWordLabel, archiveSolidLabel, archiveThreadsLabel, archiveVolumesLabel, archiveParametersLabel
    case archiveUpdateLabel, archivePathModeLabel, archiveOptionsGroup, archiveDeleteAfter, archiveEncryptionGroup, archivePasswordLabel
    case archivePasswordRepeatLabel, archiveShowPassword, archiveEncryptionMethodLabel, archiveEncryptNames, archiveAuto, archiveLevelStore
    case archiveLevelFastest, archiveLevelFast, archiveLevelNormal, archiveLevelMaximum, archiveLevelUltra, archiveSolidOff
    case archiveSolidOn, archiveUpdateAddReplace, archiveUpdateAddUpdate, archiveUpdateFreshen, archiveUpdateSync, archivePathRelative
    case archivePathFull, archivePathAbsolute, archiveBadDestination, archiveBadVolumeSize, archivePasswordMismatch, archivePasswordASCII

    // Названия действий для «Отменить …»
    case actionCopy, actionMove, actionDelete, actionRename, actionNewFolder, actionNewDocument

    // Переименование
    case renameTitle, renamePrompt

    // Свойства
    case propertiesTitle, readOnly, hidden
    case propType, propLocation, propSize, propContains, propCreated, propModified, propAttributes
    case filesAndFolders

    // Панель поиска
    case searchHeading, searchNamePrompt, searchWhere, searchButton
    case searchScopeCurrent, searchScopeHome, searchScopeComputer

    // Тема оформления
    case theme, themeXP, themeWin10

    // Окна
    case separateDockIcons, cannotOpenWindow

    // Windows 10: места
    case thisPC, quickAccess, recentLocations

    // Windows 10: лента — вкладки и группы
    case ribbonHome, ribbonShare, minimizeRibbon, expandRibbon
    case groupClipboard, groupOrganize, groupSelect, groupSend, groupPanes, groupLayout, groupCurrentView, groupShowHide

    // Windows 10: лента — команды
    case pinToQuickAccess, unpinFromQuickAccess, moveTo, copyTo, ribbonNewFolder, newItem, selectNone
    case share, email, zip, navigationPane, sortBy, hiddenItems, chooseLocation

    // Windows 10: поиск и строка состояния
    case searchPlaceholder, itemsCount, itemsCountOne, itemsSelected, itemSelectedOne

    // Смена языка
    case languageChangedTitle, languageChangedText, restartNow

    // «Открыть с помощью»
    case openWith, openWithDefault, openWithOther, openWithNoApps, cannotOpenWith

    // Удаление без корзины
    case deletePermanently, confirmDeletePermanentOne, confirmDeletePermanentMany, deleting

    // Расширения имён файлов
    case hideExtensions, fileNameExtensions

    // Перетаскивание правой кнопкой и ярлыки
    case dropCopyHere, dropMoveHere, dropShortcutsHere, dropCancel
    case shortcutTo, shortcutToNumbered, nameShortcut, nameShortcutNumbered
    case cannotCreateShortcut, actionCreateShortcut
}
