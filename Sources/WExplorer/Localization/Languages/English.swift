extension Language {
    static let english = Language(code: "en", name: "English", strings: [
        // Common buttons and words
        .ok: "OK",
        .cancel: "Cancel",
        .yes: "Yes",
        .yesToAll: "Yes to All",
        .no: "No",
        .close: "Close",
        .later: "Later",
        .cancelling: "Cancelling...",
        .calculating: "Calculating...",

        // Special places
        .myComputer: "My Computer",
        .desktop: "Desktop",
        .myDocuments: "My Documents",
        .homeFolder: "Home Folder",
        .searchResults: "Search Results: {0}",

        // Item types
        .typeFolder: "File Folder",
        .typeFile: "File",
        .typeSystemFolder: "System Folder",
        .diskLocal: "Local Disk",
        .diskRemovable: "Removable Disk",
        .diskNetwork: "Network Drive",
        .diskFree: "{0} free of {1}",

        // Units and formats
        .unitBytes: "bytes",
        .unitKB: "KB",
        .unitMB: "MB",
        .unitGB: "GB",
        .unitTB: "TB",
        .dateFormat: "M/d/yyyy h:mm a",

        // Views and columns
        .viewThumbnails: "Thumbnails",
        .viewTiles: "Tiles",
        .viewIcons: "Icons",
        .viewList: "List",
        .viewDetails: "Details",
        .columnName: "Name",
        .columnSize: "Size",
        .columnType: "Type",
        .columnModified: "Date Modified",
        .sortModified: "Date Modified",

        // Menu titles
        .menuFile: "File",
        .menuEdit: "Edit",
        .menuView: "View",
        .menuFavorites: "Favorites",
        .menuTools: "Tools",
        .menuHelp: "Help",
        .menuGo: "Go To",
        .menuWindow: "Window",

        // File menu
        .newWindow: "New Window",
        .newFolder: "New Folder",
        .newTextDocument: "New Text Document",
        .open: "Open",
        .openInNewWindow: "Open in New Window",
        .showInFinder: "Show in Finder",
        .delete: "Delete",
        .rename: "Rename",
        .properties: "Properties",

        // Edit menu
        .undo: "Undo",
        .redo: "Redo",
        .cut: "Cut",
        .copy: "Copy",
        .paste: "Paste",
        .moveHere: "Move Here",
        .copyPath: "Copy Path",
        .copyToFolder: "Copy To Folder...",
        .moveToFolder: "Move To Folder...",
        .selectAll: "Select All",
        .invertSelection: "Invert Selection",
        .move: "Move",

        // Go to
        .back: "Back",
        .forward: "Forward",
        .up: "Up",
        .upOneLevel: "Up One Level",
        .goToFolder: "Go To Folder...",

        // View menu
        .explorerBar: "Explorer Bar",
        .search: "Search",
        .folders: "Folders",
        .views: "Views",
        .arrangeIcons: "Arrange Icons By",
        .hiddenFiles: "Hidden Files",
        .refresh: "Refresh",

        // Favorites
        .addToFavorites: "Add to Favorites",
        .removeFromFavorites: "Remove from Favorites",
        .addedToFavorites: "Added to Favorites: {0}",

        // Tools
        .openInTerminal: "Open in Terminal",
        .showHiddenFiles: "Show Hidden Files",
        .systemSettings: "System Settings...",
        .language: "Language",

        // Help and app menu
        .keyboardShortcuts: "Keyboard Shortcuts",
        .shortcutsText: """
            Enter — open
            Backspace — up one level
            Cmd+[  /  Cmd+]  or  Option+←/→ — back / forward
            Cmd+↑ — up one level,  Cmd+↓ — open
            Cmd+L — go to folder (address bar)

            Cmd+C / Cmd+X / Cmd+V — copy / cut / paste
            Cmd+Option+V — move here
            Cmd+Option+C — copy path
            Cmd+Backspace or Fn+Delete — move to Trash
            F2 — rename
            Cmd+Shift+N — new folder
            Cmd+Z / Cmd+Shift+Z — undo / redo
            Cmd+I — properties

            Cmd+double-click, middle click — open folder in a new window
            Cmd+click in the folder tree or Other Places — open in a new window

            Cmd+1…5 — thumbnails, tiles, icons, list, details
            Cmd+F — search,  Cmd+Option+F — folder tree
            Cmd+Shift+. — hidden files
            Cmd+R or F5 — refresh
            Cmd+N — new window
            """,
        .about: "About {0}",
        .hideApp: "Hide {0}",
        .hideOthers: "Hide Others",
        .quitApp: "Quit {0}",
        .minimize: "Minimize",
        .zoom: "Zoom",
        .bringAllToFront: "Bring All to Front",

        // Context menu "New"
        .create: "New",
        .createFolder: "Folder",
        .createTextDocument: "Text Document",

        // Address bar
        .address: "Address",
        .go: "Go",
        .placesList: "Places",

        // Task pane
        .systemTasks: "System Tasks",
        .viewSystemInfo: "View system information",
        .changeSettings: "Change a setting",
        .fileAndFolderTasks: "File and Folder Tasks",
        .otherPlaces: "Other Places",
        .details: "Details",
        .makeNewFolder: "Make a new folder",
        .taskRenameFile: "Rename this file",
        .taskRenameFolder: "Rename this folder",
        .taskMoveFile: "Move this file",
        .taskMoveFolder: "Move this folder",
        .taskMoveItems: "Move the selected items",
        .taskCopyFile: "Copy this file",
        .taskCopyFolder: "Copy this folder",
        .taskCopyItems: "Copy the selected items",
        .taskDeleteFile: "Delete this file",
        .taskDeleteFolder: "Delete this folder",
        .taskDeleteItems: "Delete the selected items",
        .modifiedAt: "Date Modified: {0}",
        .sizeIs: "Size: {0}",
        .totalSize: "Total size: {0}",
        .searchFor: "Search for “{0}”",
        .searchIn: "In: {0}",

        // Status bar
        .objectsCount: "{0} objects",
        .selectedCount: "{0} objects selected",
        .foundCount: "{0} objects found",
        .freeSpace: " (Disk free space: {0})",
        .searching: "Searching...",
        .noAccess: "Access denied",
        .cutStatus: "{0} objects cut. Paste them into a folder (Cmd+V).",
        .copiedStatus: "{0} objects copied.",
        .pathCopied: "Path copied: {0}",
        .pathsCopied: "{0} paths copied",

        // Navigation errors
        .noAccessTitle: "“{0}” is not accessible.",
        .noAccessFullDisk: "Access is denied. To open this folder, give {0} Full Disk Access: System Settings → Privacy & Security → Full Disk Access.",
        .cannotFind: "Cannot find “{0}”.",
        .checkSpelling: "Make sure the name is spelled correctly and try again.",

        // Choosing a destination for copy/move
        .chooseCopyDestination: "Select the place where you want to copy {0}, then click the “{1}” button.",
        .chooseMoveDestination: "Select the place where you want to move {0}, then click the “{1}” button.",
        .selectedItemsCount: "the selected items ({0})",
        .quotedName: "“{0}”",

        // Confirmations
        .confirmReplaceTitle: "Confirm Replace",
        .confirmReplaceText: "This folder already contains an item named “{0}”.\n\nDo you want to replace it? The existing item will be moved to the Trash.",
        .confirmDeleteFileTitle: "Confirm File Delete",
        .confirmDeleteFolderTitle: "Confirm Folder Delete",
        .confirmDeleteOne: "Are you sure you want to move “{0}” to the Trash?",
        .confirmDeleteManyTitle: "Confirm Multiple File Delete",
        .confirmDeleteMany: "Are you sure you want to move these {0} items to the Trash?",

        // File operations
        .copying: "Copying...",
        .moving: "Moving...",
        .progressFromTo: "From “{0}” to “{1}”",
        .copyFailedSome: "Some items could not be copied",
        .moveFailedSome: "Some items could not be moved",
        .cannotCopyItem: "Cannot copy “{0}”",
        .cannotMoveItem: "Cannot move “{0}”",
        .destinationInsideSource: "The destination folder is a subfolder of the source folder.",
        .copyOfName: "Copy of {0}",
        .copyOfNameNumbered: "Copy ({1}) of {0}",
        .cannotMove: "Cannot move “{0}”",
        .cannotDelete: "Cannot delete “{0}”",
        .invalidCharacters: "A file name can't contain any of the following characters:",
        .cannotRename: "Cannot rename “{0}”",
        .nameExists: "An item named “{0}” already exists. Specify a different name.",
        .newFolderName: "New Folder",
        .newFolderNameNumbered: "New Folder ({0})",
        .cannotCreateFolder: "Cannot create the folder",
        .newTextDocumentName: "New Text Document",
        .newTextDocumentNameNumbered: "New Text Document ({0})",
        .cannotCreateTextDocument: "Cannot create the text document",
        .noWritePermission: "You may not have permission to write to this folder.",

        // Archives
        .archiveMenu: "Archive",
        .archiveExtract: "Extract",
        .archiveExtractEllipsis: "Extract Files...",
        .archiveExtractHere: "Extract Here",
        .archiveExtractTo: "Extract to “{0}”",
        .archiveExtractToEach: "Extract Each to Its Own Folder",
        .archiveTest: "Test Archive",
        .archiveAddTo: "Add to “{0}”",
        .archiveChooseDestination: "Select the folder where you want to extract {0}.",
        .archiveExtracting: "Extracting...",
        .archiveTesting: "Testing Archive...",
        .archiveCompressing: "Compressing...",
        .archiveTestPassed: "There are no errors",
        .archiveFailed: "The archive operation failed",
        .archiveCannotRun: "Cannot run the archiver.",
        .archiveEncryptionUnsupported: "The built-in archiver does not support this archive's encryption. You can extract it with 7-Zip.",
        .archiveEnterPassword: "Enter the archive password",
        .archiveWrongPassword: "Wrong password. Try again",
        .archiveAddDialog: "Add to Archive...",
        .archiveAddTitle: "Add to Archive",
        .archiveFieldArchive: "Archive:",
        .archiveFormatLabel: "Archive format:",
        .archiveLevelLabel: "Compression level:",
        .archiveMethodLabel: "Compression method:",
        .archiveDictionaryLabel: "Dictionary size:",
        .archiveWordLabel: "Word size:",
        .archiveSolidLabel: "Solid block size:",
        .archiveThreadsLabel: "Number of CPU threads:",
        .archiveVolumesLabel: "Split to volumes, bytes:",
        .archiveParametersLabel: "Parameters:",
        .archiveUpdateLabel: "Update mode:",
        .archivePathModeLabel: "Path mode:",
        .archiveOptionsGroup: "Options",
        .archiveDeleteAfter: "Delete files after compression (to Trash)",
        .archiveEncryptionGroup: "Encryption",
        .archivePasswordLabel: "Enter password:",
        .archivePasswordRepeatLabel: "Reenter password:",
        .archiveShowPassword: "Show password",
        .archiveEncryptionMethodLabel: "Encryption method:",
        .archiveEncryptNames: "Encrypt file names",
        .archiveAuto: "Auto",
        .archiveLevelStore: "Store",
        .archiveLevelFastest: "Fastest",
        .archiveLevelFast: "Fast",
        .archiveLevelNormal: "Normal",
        .archiveLevelMaximum: "Maximum",
        .archiveLevelUltra: "Ultra",
        .archiveSolidOff: "Non-solid",
        .archiveSolidOn: "Solid",
        .archiveUpdateAddReplace: "Add and replace files",
        .archiveUpdateAddUpdate: "Update and add files",
        .archiveUpdateFreshen: "Freshen existing files",
        .archiveUpdateSync: "Synchronize files",
        .archivePathRelative: "Relative pathnames",
        .archivePathFull: "Full pathnames",
        .archivePathAbsolute: "Absolute pathnames",
        .archiveBadDestination: "Invalid archive location",
        .archiveBadVolumeSize: "Invalid volume size",
        .archivePasswordMismatch: "The passwords do not match",
        .archivePasswordASCII: "A zip password can contain only Latin letters, digits and symbols. Use such a password or the 7z format.",

        // Action names for "Undo …"
        .actionCopy: "Copy",
        .actionMove: "Move",
        .actionDelete: "Delete",
        .actionRename: "Rename",
        .actionNewFolder: "New Folder",
        .actionNewDocument: "New Document",

        // Rename
        .renameTitle: "Rename",
        .renamePrompt: "New name for “{0}”:",

        // Properties
        .propertiesTitle: "{0} Properties",
        .readOnly: "Read-only",
        .hidden: "Hidden",
        .propType: "Type:",
        .propLocation: "Location:",
        .propSize: "Size:",
        .propContains: "Contains:",
        .propCreated: "Created:",
        .propModified: "Modified:",
        .propAttributes: "Attributes:",
        .filesAndFolders: "{0} Files, {1} Folders",

        // Search pane
        .searchHeading: "Search for files and folders",
        .searchNamePrompt: "All or part of the file name:",
        .searchWhere: "Look in:",
        .searchButton: "Search",
        .searchScopeCurrent: "In the current folder",
        .searchScopeHome: "In the home folder",
        .searchScopeComputer: "On the entire computer",

        // Language change
        .languageChangedTitle: "Interface language changed",
        .languageChangedText: "The new language will be applied after {0} restarts.",
        .restartNow: "Restart Now",
    ])
}
