import SwiftUI
#if os(macOS)
import AppKit
#endif

// MOCKUP ONLY. Fake data, no MySQL.

struct FakeConnection: Identifiable {
    let id: String
    let name: String
    let detail: String
    let databases: [String]
    let systemDatabases: [String]
}

struct FakeHistoryRow: Identifiable {
    let id: String
    let when: String
    let source: String
    let destination: String
    let ok: Bool
}

struct ContentView: View {
    @Bindable var model: AppModel

    private let prototypeConnections: [FakeConnection] = [
        FakeConnection(
            id: "welcome_prod",
            name: "Welcome Production",
            detail: "prod.welcome.it · SSH",
            databases: ["welcome_prod", "welcome_staging", "analytics"],
            systemDatabases: ["information_schema", "mysql", "performance_schema", "sys"]
        ),
        FakeConnection(
            id: "voila_prod",
            name: "Voilà Production",
            detail: "prod.voila.it · SSH",
            databases: ["voila"],
            systemDatabases: ["information_schema", "mysql", "sys"]
        ),
        FakeConnection(
            id: "localhost",
            name: "Localhost",
            detail: "127.0.0.1:3306",
            databases: ["welcome", "welcome_test", "voila", "spicciolo"],
            systemDatabases: ["information_schema", "mysql", "performance_schema", "sys"]
        )
    ]

    @State private var selectedNav = ""
    @State private var selectedRecipeId = ""
    @State private var sourceDatabase = ""
    @State private var destinationConnectionId = ""
    @State private var destinationDatabase = ""
    @State private var strategy = "backup"
    @State private var replaceMode = ReplaceMode.importInPlace.rawValue
    @State private var newDatabaseName = "welcome_fresh"
    @State private var backupName = "welcome_backup_20260918_1515"
    @State private var showSystemDatabases = false
    @State private var showConfirm = false
    @State private var tableScope = "all"
    @State private var selectedTableNames: Set<String> = []
    @State private var skipTableReset = false
    @State private var skipDestinationLoad = false
    @State private var showSaveRecipeName = false
    @State private var newRecipeTitle = ""
    @State private var showOverwriteRecipeConfirm = false
    @State private var connectionToDelete: Connection?
    @State private var showClearHistoryConfirm = false
    @State private var historySortOrder = HistoryDisplay.defaultSortOrder
    @State private var recipeSavedMessage: String?
    @State private var recipeSavedClearTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            mainArea
        }
        .preferredColorScheme(.light)
        .background(Color.white)
        .frame(minWidth: 980, idealWidth: 980, minHeight: 720, idealHeight: 840)
        .sheet(isPresented: $showConfirm) {
            confirmSheet
                .preferredColorScheme(.light)
        }
        .sheet(isPresented: Binding(
            get: { model.showNewConnection },
            set: { showing in
                if showing {
                    model.showNewConnection = true
                } else {
                    model.cancelConnectionForm()
                }
            }
        )) {
            newConnectionSheet
                .preferredColorScheme(.light)
        }
        .sheet(isPresented: $showSaveRecipeName) {
            saveRecipeNameSheet
                .preferredColorScheme(.light)
        }
        .confirmationDialog(
            "Overwrite Recipe?",
            isPresented: $showOverwriteRecipeConfirm,
            titleVisibility: .visible
        ) {
            Button("Overwrite") {
                persistSelectedRecipe()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let recipe = selectedRecipe {
                Text("This replaces “\(recipe.title)” with the current form. You cannot undo it.")
            } else {
                Text("This replaces the saved Recipe with the current form. You cannot undo it.")
            }
        }
        .confirmationDialog(
            "Delete Connection?",
            isPresented: Binding(
                get: { connectionToDelete != nil },
                set: { if $0 == false { connectionToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                confirmDeleteConnection()
            }
            Button("Cancel", role: .cancel) {
                connectionToDelete = nil
            }
        } message: {
            if let connection = connectionToDelete {
                Text("This removes \(connection.name), its Keychain secrets, and Recipes that use it as source. History is not changed.")
            }
        }
        .onAppear {
            if selectedNav.isEmpty, let first = model.connections.first {
                selectNav(first.id.uuidString)
            }
        }
        .onChange(of: selectedRecipeId) { _, id in
            if let uuid = UUID(uuidString: id),
               let recipe = model.recipes.first(where: { $0.id == uuid }) {
                applyRecipe(recipe)
                skipDestinationLoad = false
                if let source = realSelectedConnection {
                    loadDatabasesForCurrentEnds(source: source)
                }
            }
        }
        .onChange(of: sourceDatabase) { _, _ in
            if skipTableReset {
                skipTableReset = false
                return
            }
            if tableScope == "choose" {
                selectedTableNames = []
                if let recipe = selectedRecipe,
                   recipe.tables.isEmpty == false,
                   recipe.sourceDatabase == sourceDatabase {
                    selectedTableNames = Set(recipe.tables)
                }
                loadTablesForSource()
                return
            }
            selectedTableNames = []
        }
        .onChange(of: destinationConnectionId) { _, id in
            if skipDestinationLoad {
                return
            }
            if let dest = model.connections.first(where: { $0.id.uuidString == id }) {
                model.loadDatabases(for: dest, force: false)
            }
        }
        .onChange(of: destinationDatabase) { _, name in
            backupName = BackupName.defaultName(database: name, at: Date())
        }
        .onChange(of: tableScope) { _, scope in
            if scope == "choose" {
                replaceMode = ReplaceMode.importInPlace.rawValue
                loadTablesForSource()
            }
        }
    }

    private var selectedConnection: FakeConnection? {
        prototypeConnections.first { $0.id == selectedNav }
    }

    private var destinationConnection: FakeConnection? {
        prototypeConnections.first { $0.id == destinationConnectionId }
    }

    private var realSelectedConnection: Connection? {
        model.connections.first { $0.id.uuidString == selectedNav }
    }

    private var recipesForSelectedSource: [Recipe] {
        guard let source = realSelectedConnection else {
            return []
        }
        return Recipe.forSource(connectionId: source.id, in: model.recipes)
    }

    private var recipeMenuOptions: [(id: String, title: String)] {
        var options = [(id: "", title: "None")]
        for recipe in recipesForSelectedSource {
            options.append((id: recipe.id.uuidString, title: recipe.title))
        }
        return options
    }

    private func databasePickerOptions(
        for connection: Connection,
        selected: String
    ) -> [(id: String, title: String)] {
        DatabasePickerOptions.menu(
            liveNames: model.databaseNamesByConnectionId[connection.id] ?? [],
            selected: selected,
            showSystem: showSystemDatabases
        ).map { (id: $0.id, title: $0.title) }
    }

    private var realDestinationConnection: Connection? {
        model.connections.first { $0.id.uuidString == destinationConnectionId }
    }

    private func loadDatabasesForCurrentEnds(source: Connection) {
        model.loadSourceThenDestination(
            source: source,
            destination: realDestinationConnection,
            force: false
        )
    }

    private func copyText(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private var strategyLabel: String {
        if strategy == "replace" { return "Replace" }
        if strategy == "create" { return "Create new" }
        return "Backup and replace"
    }

    private var selectedRecipe: Recipe? {
        guard let uuid = UUID(uuidString: selectedRecipeId) else {
            return nil
        }
        return model.recipes.first { $0.id == uuid }
    }

    private var tableChecklist: [TablePickerOption] {
        TablePickerOptions.checklist(
            liveNames: model.liveTableNames,
            keptNames: Array(selectedTableNames)
        )
    }

    private func loadTablesForSource() {
        guard let source = realSelectedConnection else {
            return
        }
        model.loadTables(for: source, database: sourceDatabase)
    }

    private var chosenTableNames: [String] {
        tableChecklist.map(\.id).filter { selectedTableNames.contains($0) }
    }

    private var tablesSummary: String {
        if tableScope == "all" {
            return "All tables"
        }
        if chosenTableNames.isEmpty {
            return "No tables selected"
        }
        return chosenTableNames.joined(separator: ", ")
    }

    private var pullDestinationName: String {
        strategy == "create" ? newDatabaseName : destinationDatabase
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            appLogo
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)

            List {
                ForEach(model.connections) { connection in
                    connectionSidebarRow(connection)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .onMove { fromOffsets, toOffset in
                    model.moveConnections(fromOffsets: fromOffsets, toOffset: toOffset)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
            .frame(maxHeight: .infinity)

            Button {
                model.beginNewConnection()
            } label: {
                Label("New Connection", systemImage: "plus")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.15, green: 0.42, blue: 0.95))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Spacer()

            sidebarButton(id: "history", title: "History", icon: "clock")
            sidebarButton(id: "settings", title: "Settings", icon: "gearshape")
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 10)
        .frame(width: 230)
        .background(Color(red: 0.965, green: 0.973, blue: 0.984))
    }

    private var appLogo: some View {
        VStack(spacing: 10) {
            Image("AppLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("UmpaDumpa")
                .font(.system(size: 15, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
    }

    private func connectionSidebarRow(_ connection: Connection) -> some View {
        let id = connection.id.uuidString
        let isSelected = selectedNav == id
        let icon = connection.name.lowercased() == "localhost" ? "laptopcomputer" : "externaldrive.fill"

        return Button {
            selectNav(id)
        } label: {
            Label(connection.name, systemImage: icon)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(
                    isSelected
                        ? Color(red: 0.15, green: 0.42, blue: 0.95)
                        : Color(red: 0.35, green: 0.40, blue: 0.48)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color(red: 0.86, green: 0.92, blue: 1.0) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .labelStyle(.titleAndIcon)
        .contextMenu {
            Button("Edit…") {
                model.beginEditConnection(connection)
            }
            Button("Delete…", role: .destructive) {
                connectionToDelete = connection
            }
        }
    }

    private func confirmDeleteConnection() {
        guard let connection = connectionToDelete else {
            return
        }
        let deletedId = connection.id.uuidString
        model.deleteConnection(id: connection.id)
        connectionToDelete = nil

        if selectedNav == deletedId {
            if let first = model.connections.first {
                selectNav(first.id.uuidString)
            } else {
                selectedNav = ""
            }
        }

        if destinationConnectionId == deletedId {
            destinationConnectionId = model.connections.first { $0.name.lowercased() == "localhost" }?.id.uuidString
                ?? model.connections.first?.id.uuidString
                ?? ""
        }
    }

    private func sidebarButton(id: String, title: String, icon: String) -> some View {
        let isSelected = selectedNav == id

        return Button {
            selectNav(id)
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(
                    isSelected
                        ? Color(red: 0.15, green: 0.42, blue: 0.95)
                        : Color(red: 0.35, green: 0.40, blue: 0.48)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color(red: 0.86, green: 0.92, blue: 1.0) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .labelStyle(.titleAndIcon)
    }

    private func selectNav(_ id: String) {
        selectedNav = id
        selectedRecipeId = ""
        skipDestinationLoad = true

        if let connection = model.connections.first(where: { $0.id.uuidString == id }) {
            sourceDatabase = ""
            destinationConnectionId = model.connections.first { $0.name.lowercased() == "localhost" }?.id.uuidString
                ?? connection.id.uuidString
            destinationDatabase = ""
            strategy = "replace"
            replaceMode = ReplaceMode.importInPlace.rawValue
            backupName = ""
            newDatabaseName = ""
            skipTableReset = true
            tableScope = "all"
            selectedTableNames = []

            loadDatabasesForCurrentEnds(source: connection)
        }
        skipDestinationLoad = false
    }

    private var mainArea: some View {
        Group {
            if selectedNav == "history" {
                historyScreen
            } else if selectedNav == "settings" {
                settingsScreen
            } else if let connection = realSelectedConnection {
                pullScreen(for: connection)
            } else {
                Text("Choose a connection")
                    .font(.system(size: 22, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.97, green: 0.975, blue: 0.98))
    }

    private var historyScreen: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History")
                    .font(.system(size: 28, weight: .bold))
                Spacer()
                Button("Clear History") {
                    showClearHistoryConfirm = true
                }
            }
            .confirmationDialog(
                "Clear History?",
                isPresented: $showClearHistoryConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear History", role: .destructive) {
                    model.clearHistory()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the whole History log. You cannot undo it.")
            }

            Table(model.history, sortOrder: $historySortOrder) {
                TableColumn("When", value: \.when) { row in
                    Text(row.when.formatted(date: .abbreviated, time: .shortened))
                }
                .width(min: 110, ideal: 140)

                TableColumn("Source", value: \.source)

                TableColumn("Destination", value: \.destination)

                TableColumn("Result", value: \.resultLabel) { row in
                    Label(
                        row.resultLabel,
                        systemImage: row.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(
                        row.succeeded
                            ? Color(red: 0.22, green: 0.78, blue: 0.40)
                            : Color(red: 0.90, green: 0.30, blue: 0.30)
                    )
                }
                .width(min: 90, ideal: 110)
            }
            .tableStyle(.inset)
        }
        .padding(28)
    }

    private var settingsScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.system(size: 28, weight: .bold))

            mockCard {
                VStack(alignment: .leading, spacing: 10) {
                    cardTitle("mysql / mysqldump", icon: "terminal")
                    Text("Leave blank to use PATH.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.45, green: 0.49, blue: 0.55))
                    fieldLabel("mysqldump path")
                    TextField("/opt/homebrew/bin/mysqldump", text: $model.mysqldumpPath)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.extraLarge)
                        .onChange(of: model.mysqldumpPath) { _, _ in
                            model.saveClientSettings()
                        }
                    fieldLabel("mysql path")
                    TextField("/opt/homebrew/bin/mysql", text: $model.mysqlPath)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.extraLarge)
                        .onChange(of: model.mysqlPath) { _, _ in
                            model.saveClientSettings()
                        }
                }
            }

            Spacer()
        }
        .padding(36)
    }

    private func pullScreen(for connection: Connection) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(connection.name)
                    .font(.system(size: 28, weight: .bold))
                Spacer()
                statusRow(text: connection.detail, ssh: connection.usesSSH)
            }
            .padding(.top, 12)

            mockCard {
                VStack(alignment: .leading, spacing: 10) {
                    cardTitle("Recipe", icon: "bookmark")
                    HStack(alignment: .center, spacing: 8) {
                        huggingPicker(
                            selection: $selectedRecipeId,
                            options: recipeMenuOptions
                        )

                        Spacer(minLength: 8)

                        if selectedRecipeId != "" {
                            Button(action: duplicateSelectedRecipe) {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.extraLarge)

                            Button(action: deleteSelectedRecipe) {
                                Label("Delete", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.extraLarge)
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 12) {
                mockCard {
                    originColumn(for: connection)
                }
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(red: 0.70, green: 0.74, blue: 0.80))
                    .padding(.top, 56)
                mockCard {
                    destinationColumn
                }
            }

            Spacer()
            pullStatusRow
            footerBar
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
        .padding(.top, 16)
        .onAppear {
            loadDatabasesForCurrentEnds(source: connection)
        }
    }

    private func tableBinding(_ tableName: String) -> Binding<Bool> {
        Binding(
            get: { selectedTableNames.contains(tableName) },
            set: { isOn in
                if isOn {
                    selectedTableNames.insert(tableName)
                } else {
                    selectedTableNames.remove(tableName)
                }
            }
        )
    }

    private func applyRecipe(_ recipe: Recipe) {
        skipTableReset = true
        skipDestinationLoad = true
        sourceDatabase = recipe.sourceDatabase
        destinationConnectionId = recipe.destinationConnectionId.uuidString
        destinationDatabase = recipe.destinationDatabase
        if recipe.strategy == .createNew {
            strategy = "create"
            newDatabaseName = recipe.destinationDatabase
        } else if recipe.strategy == .backupThenReplace {
            strategy = "backup"
            newDatabaseName = "\(recipe.sourceDatabase)_fresh"
        } else {
            strategy = "replace"
            newDatabaseName = "\(recipe.sourceDatabase)_fresh"
        }
        replaceMode = recipe.replaceMode.rawValue
        backupName = BackupName.defaultName(database: recipe.destinationDatabase, at: Date())
        if recipe.tables.isEmpty {
            tableScope = "all"
            selectedTableNames = []
        } else {
            tableScope = "choose"
            selectedTableNames = Set(recipe.tables)
            loadTablesForSource()
        }
    }

    private func resetFormForCurrentConnection() {
        skipTableReset = true
        sourceDatabase = ""
        destinationConnectionId = model.connections.first { $0.name.lowercased() == "localhost" }?.id.uuidString
            ?? realSelectedConnection?.id.uuidString
            ?? ""
        destinationDatabase = ""
        strategy = "replace"
        replaceMode = ReplaceMode.importInPlace.rawValue
        backupName = ""
        newDatabaseName = ""
        tableScope = "all"
        selectedTableNames = []
    }

    private func deleteSelectedRecipe() {
        if let uuid = UUID(uuidString: selectedRecipeId) {
            model.deleteRecipe(id: uuid)
        }
        selectedRecipeId = ""
        resetFormForCurrentConnection()
    }

    private func duplicateSelectedRecipe() {
        guard let uuid = UUID(uuidString: selectedRecipeId),
              let recipe = model.recipes.first(where: { $0.id == uuid }) else {
            return
        }
        let copy = recipe.duplicated()
        model.saveRecipe(copy)
        selectedRecipeId = copy.id.uuidString
    }

    private var canSaveRecipe: Bool {
        recipeFromCurrentForm(id: UUID(), title: "Recipe") != nil
    }

    private func recipeFromCurrentForm(id: UUID, title: String) -> Recipe? {
        guard let source = realSelectedConnection,
              let destId = UUID(uuidString: destinationConnectionId)
        else {
            return nil
        }

        let destName: String
        let strategyValue: Strategy
        if strategy == "create" {
            destName = newDatabaseName
            strategyValue = .createNew
        } else if strategy == "backup" {
            destName = destinationDatabase
            strategyValue = .backupThenReplace
        } else {
            destName = destinationDatabase
            strategyValue = .replace
        }

        if PullForm.canStartDump(
            sourceDatabase: sourceDatabase,
            strategy: strategyValue,
            destinationDatabase: destinationDatabase,
            newDatabaseName: newDatabaseName
        ) == false {
            return nil
        }

        let chosenTables = chosenTableNames
        if tableScope == "choose" && chosenTables.isEmpty {
            return nil
        }

        let mode: ReplaceMode
        if tableScope == "choose" {
            mode = .importInPlace
        } else {
            mode = ReplaceMode(rawValue: replaceMode) ?? .importInPlace
        }

        return Recipe(
            id: id,
            title: title,
            sourceConnectionId: source.id,
            sourceDatabase: sourceDatabase,
            destinationConnectionId: destId,
            destinationDatabase: destName,
            strategy: strategyValue,
            replaceMode: mode,
            tables: tableScope == "choose" ? chosenTables : []
        )
    }

    private func persistSelectedRecipe() {
        guard let uuid = UUID(uuidString: selectedRecipeId),
              let existing = model.recipes.first(where: { $0.id == uuid }),
              let updated = recipeFromCurrentForm(id: existing.id, title: existing.title)
        else {
            return
        }
        model.saveRecipe(updated)
        showRecipeSaved()
    }

    private func persistNewRecipe(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              let recipe = recipeFromCurrentForm(id: UUID(), title: trimmed)
        else {
            return
        }
        model.saveRecipe(recipe)
        selectedRecipeId = recipe.id.uuidString
        showSaveRecipeName = false
        newRecipeTitle = ""
        showRecipeSaved()
    }

    private func showRecipeSaved() {
        recipeSavedMessage = "Recipe saved."
        recipeSavedClearTask?.cancel()
        recipeSavedClearTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if Task.isCancelled {
                return
            }
            recipeSavedMessage = nil
        }
    }

    private func liveDatabasePicker(connection: Connection, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                nativePicker(
                    selection: selection,
                    options: databasePickerOptions(for: connection, selected: selection.wrappedValue)
                )
                if model.loadingDatabaseConnectionId == connection.id {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(model.databaseListErrorByConnectionId[connection.id] == nil ? "Refresh" : "Retry") {
                    model.loadDatabases(for: connection, force: true)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.15, green: 0.42, blue: 0.95))
                .disabled(model.isPulling)
            }

            if let listError = model.databaseListErrorByConnectionId[connection.id] {
                HStack(alignment: .top, spacing: 8) {
                    Text(listError)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.90, green: 0.30, blue: 0.30))
                        .textSelection(.enabled)
                    Button("Copy") {
                        copyText(listError)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.15, green: 0.42, blue: 0.95))
                }
            }
        }
    }

    private func originColumn(for connection: Connection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("Source", icon: "icloud")

            fieldLabel("Connection")
            lockedField(text: connection.name, icon: "lock.fill")

            fieldLabel("Database")
            liveDatabasePicker(connection: connection, selection: $sourceDatabase)

            Toggle("System databases", isOn: $showSystemDatabases)
                .font(.system(size: 12))
                #if os(macOS)
                .toggleStyle(.checkbox)
                #endif

            fieldLabel("Tables")
            nativePicker(
                selection: $tableScope,
                options: [
                    (id: "all", title: "All tables"),
                    (id: "choose", title: "Selected tables")
                ]
            )

            if tableScope == "choose" {
                HStack(spacing: 12) {
                    Button("Check all") {
                        selectedTableNames = Set(tableChecklist.map(\.id))
                    }
                    Button("Uncheck all") {
                        selectedTableNames = []
                    }
                    if model.isLoadingTables {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button(model.tableListError == nil ? "Refresh" : "Retry") {
                        loadTablesForSource()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.15, green: 0.42, blue: 0.95))
                    .disabled(model.isPulling)
                }
                .font(.system(size: 12))
                .buttonStyle(.plain)
                .foregroundStyle(Color(red: 0.15, green: 0.42, blue: 0.95))

                if let listError = model.tableListError {
                    HStack(alignment: .top, spacing: 8) {
                        Text(listError)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 0.90, green: 0.30, blue: 0.30))
                            .textSelection(.enabled)
                        Button("Copy") {
                            copyText(listError)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.15, green: 0.42, blue: 0.95))
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(tableChecklist, id: \.id) { option in
                            Toggle(option.title, isOn: tableBinding(option.id))
                                .font(.system(size: 12))
                                #if os(macOS)
                                .toggleStyle(.checkbox)
                                #endif
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)

                if selectedTableNames.isEmpty {
                    Text("Choose at least one table.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.90, green: 0.30, blue: 0.30))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var destinationColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("Destination", icon: "internaldrive")

            fieldLabel("Connection")
            nativePicker(
                selection: $destinationConnectionId,
                options: model.connections.map { (id: $0.id.uuidString, title: $0.name) }
            )

            if strategy != "create", let dest = realDestinationConnection {
                fieldLabel("Database")
                liveDatabasePicker(connection: dest, selection: $destinationDatabase)
            }

            fieldLabel("Strategy")

            operationChoice(id: "replace", title: "Replace", icon: "trash")
            operationChoice(id: "backup", title: "Backup and replace", icon: "archivebox")
            operationChoice(id: "create", title: "Create new", icon: "plus.square")

            if strategy == "backup" {
                TextField("Backup name", text: $backupName)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.extraLarge)
            }

            if strategy == "create" {
                TextField("Database name", text: $newDatabaseName)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.extraLarge)
            }

            if tableScope == "all" && (strategy == "replace" || strategy == "backup") {
                fieldLabel("Replace mode")
                replaceModeChoice(
                    id: ReplaceMode.dropDatabase.rawValue,
                    title: "Drop database, then import",
                    icon: "trash"
                )
                replaceModeChoice(
                    id: ReplaceMode.importInPlace.rawValue,
                    title: "Import in place",
                    icon: "square.and.pencil"
                )
            }

            if tableScope == "choose" && (strategy == "replace" || strategy == "backup") {
                fieldLabel("Replace mode")
                Text("Import in place (subset Pulls do not drop the destination Database)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.45, green: 0.49, blue: 0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pullStatusRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let recipeSavedMessage {
                Text(recipeSavedMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.16, green: 0.55, blue: 0.30))
            }

            if model.isPulling {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(pullStatusText)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(red: 0.12, green: 0.14, blue: 0.20))
                }
            } else if model.pullPhase == .succeeded {
                Text("Done. The Pull succeeded. See History for the log.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.16, green: 0.55, blue: 0.30))
                    .textSelection(.enabled)
            }

            if let error = model.pullError {
                HStack(alignment: .top, spacing: 8) {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.90, green: 0.30, blue: 0.30))
                        .textSelection(.enabled)
                    Button("Copy error") {
                        copyErrorToClipboard(error)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var pullStatusText: String {
        let progress = model.pullProgress
        if progress.phase == .importingDestination {
            return "Importing destination…"
        }

        var text = "Dumping source…"
        if progress.phase == .creatingBackup {
            text = "Creating Backup…"
        }
        if progress.phase == .dumpingSource || progress.phase == .creatingBackup {
            if progress.tablesTotal > 0 {
                text += " \(progress.tablesReached) of \(progress.tablesTotal) tables"
            }
            if let megabytes = progress.dumpFileMegabytes {
                text += " · \(megabytes) MB"
            }
        }
        return text
    }

    private var footerBar: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.bottom, 14)

            HStack {
                Button {
                    if selectedRecipeId.isEmpty {
                        newRecipeTitle = ""
                        showSaveRecipeName = true
                    } else {
                        showOverwriteRecipeConfirm = true
                    }
                } label: {
                    Label("Save recipe", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.extraLarge)
                .disabled(canSaveRecipe == false)

                Spacer()

                Button {
                    showConfirm = true
                } label: {
                    Label(model.isPulling ? "Dumping…" : "Start dump", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                .disabled(model.isPulling || currentPullRequest() == nil)
            }
        }
    }

    private var confirmSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirm dump")
                .font(.system(size: 20, weight: .bold))

            if let uuid = UUID(uuidString: selectedRecipeId),
               let recipe = model.recipes.first(where: { $0.id == uuid }) {
                confirmLine("Recipe", recipe.title, icon: "bookmark")
            }
            if let summary = confirmSummaryForSheet {
                confirmLine("Source", summary.sourceLabel, icon: "icloud")
                confirmLine("Destination", summary.destinationLabel, icon: "internaldrive")
                confirmLine("Strategy", summary.strategyLabel, icon: "gearshape")
                if strategy != "create" {
                    confirmLine("Replace mode", summary.replaceModeLabel, icon: "square.and.pencil")
                }
                confirmLine("Tables", summary.tablesLabel, icon: "tablecells")
                if summary.backupNameLabel.isEmpty == false {
                    confirmLine("Backup name", summary.backupNameLabel, icon: "archivebox")
                }
                if summary.request.tables.isEmpty == false {
                    Text("Will not drop the destination Database. Only these tables are replaced.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.45, green: 0.49, blue: 0.55))
                }
            }

            if strategy == "backup" {
                TextField("Backup name", text: $backupName)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.extraLarge)
            }

            HStack {
                Spacer()
                Button("Cancel") { showConfirm = false }
                    .buttonStyle(.bordered)
                    .controlSize(.extraLarge)
                Button {
                    runPullFromConfirm()
                } label: {
                    Label("Start dump", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                .disabled(model.isPulling || currentPullRequest() == nil)
            }
        }
        .padding(28)
        .frame(width: 480)
        .background(Color.white)
    }

    private var confirmSummaryForSheet: ConfirmSummary? {
        guard let request = currentPullRequest() else {
            return nil
        }
        return model.engine.confirm(request)
    }

    private func currentPullRequest() -> PullRequest? {
        guard let source = realSelectedConnection,
              let dest = model.connections.first(where: { $0.id.uuidString == destinationConnectionId }),
              sourceDatabase.isEmpty == false
        else {
            return nil
        }

        let destName: String
        let strategyValue: Strategy
        if strategy == "create" {
            destName = newDatabaseName
            strategyValue = .createNew
        } else if strategy == "backup" {
            destName = destinationDatabase
            strategyValue = .backupThenReplace
        } else {
            destName = destinationDatabase
            strategyValue = .replace
        }

        if PullForm.canStartDump(
            sourceDatabase: sourceDatabase,
            strategy: strategyValue,
            destinationDatabase: destinationDatabase,
            newDatabaseName: newDatabaseName
        ) == false {
            return nil
        }

        let chosenTables = chosenTableNames
        if tableScope == "choose" && chosenTables.isEmpty {
            return nil
        }

        let mode: ReplaceMode
        if tableScope == "choose" {
            mode = .importInPlace
        } else {
            mode = ReplaceMode(rawValue: replaceMode) ?? .importInPlace
        }

        return PullRequest(
            sourceConnection: source,
            sourceDatabase: sourceDatabase,
            destinationConnection: dest,
            destinationDatabase: destName,
            strategy: strategyValue,
            replaceMode: mode,
            tables: tableScope == "choose" ? chosenTables : [],
            backupName: strategy == "backup" ? backupName : "",
            recipeId: UUID(uuidString: selectedRecipeId)
        )
    }

    private func runPullFromConfirm() {
        guard let request = currentPullRequest() else {
            return
        }
        let summary = model.engine.confirm(request)
        showConfirm = false
        model.pullError = nil
        model.pullPhase = .dumpingSource
        model.pullProgress = PullProgress(phase: .dumpingSource, tablesReached: 0, tablesTotal: 0, dumpFileMegabytes: nil)
        model.isPulling = true
        Task {
            defer { model.isPulling = false }
            do {
                _ = try await model.engine.run(summary)
                model.pullError = nil
                model.pullPhase = .succeeded
                model.refreshHistory()
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    if model.pullPhase == .succeeded {
                        model.pullPhase = .idle
                    }
                }
            } catch PullError.alreadyRunning {
                model.pullPhase = .failed
                model.pullError = "A Pull is already running."
                model.refreshHistory()
            } catch let PullError.dumpFailed(detail) {
                model.pullPhase = .failed
                let extra = detail.isEmpty ? "" : " \(detail)"
                model.pullError = "Dump failed. Destination was not changed.\(extra)"
                model.refreshHistory()
            } catch PullError.tunnelFailed {
                model.pullPhase = .failed
                model.pullError = "SSH tunnel failed. Destination was not changed."
                model.refreshHistory()
            } catch PullError.missingClient(.mysqldump) {
                model.pullPhase = .failed
                model.pullError = "mysqldump was not found. Set its path in Settings."
                model.refreshHistory()
            } catch PullError.missingClient(.mysql) {
                model.pullPhase = .failed
                model.pullError = "mysql was not found. Set its path in Settings."
                model.refreshHistory()
            } catch PullError.nameAlreadyExists {
                model.pullPhase = .failed
                model.pullError = "That name already exists. The destination was not changed."
                model.refreshHistory()
            } catch PullError.importFailed {
                model.pullPhase = .failed
                model.pullError = "Import failed."
                model.refreshHistory()
            } catch {
                model.pullPhase = .failed
                model.pullError = "Pull failed."
                model.refreshHistory()
            }
        }
    }

    private var newConnectionSheet: some View {
        let isEditing = model.editingConnectionId != nil

        return VStack(alignment: .leading, spacing: 12) {
            Text(isEditing ? "Edit Connection" : "New Connection")
                .font(.system(size: 20, weight: .bold))

            TextField("Name", text: $model.newName)
                .textFieldStyle(.roundedBorder)
            TextField("Host", text: $model.newHost)
                .textFieldStyle(.roundedBorder)
            TextField("Port", text: $model.newPort)
                .textFieldStyle(.roundedBorder)
            TextField("User", text: $model.newUser)
                .textFieldStyle(.roundedBorder)
            SecureField("Password", text: $model.newPassword)
                .textFieldStyle(.roundedBorder)

            Toggle("SSH tunnel", isOn: $model.newUsesSSH)
            if model.newUsesSSH {
                TextField("SSH host", text: $model.newSSHHost)
                    .textFieldStyle(.roundedBorder)
                TextField("SSH port", text: $model.newSSHPort)
                    .textFieldStyle(.roundedBorder)
                TextField("SSH user", text: $model.newSSHUser)
                    .textFieldStyle(.roundedBorder)
                Picker("SSH auth", selection: $model.newSSHAuth) {
                    Text("Password").tag(SSHAuthMethod.password.rawValue)
                    Text("Private key").tag(SSHAuthMethod.privateKey.rawValue)
                }
                if model.newSSHAuth == SSHAuthMethod.privateKey.rawValue {
                    TextField("Private key path (.pem)", text: $model.newSSHKeyPath)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Key passphrase", text: $model.newSSHPassphrase)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField("SSH password", text: $model.newSSHPassword)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                if isEditing {
                    Button("Delete…", role: .destructive) {
                        if let id = model.editingConnectionId,
                           let connection = model.connections.first(where: { $0.id == id }) {
                            model.cancelConnectionForm()
                            connectionToDelete = connection
                        }
                    }
                }
                Spacer()
                Button("Cancel") {
                    model.cancelConnectionForm()
                }
                Button("Save") {
                    if isEditing {
                        _ = model.updateConnectionFromForm()
                    } else {
                        let connection = model.addConnection()
                        selectNav(connection.id.uuidString)
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.newName.isEmpty || model.newHost.isEmpty || model.newUser.isEmpty)
            }
        }
        .padding(28)
        .frame(width: 420)
        .background(Color.white)
    }

    private var saveRecipeNameSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save recipe")
                .font(.system(size: 20, weight: .bold))

            TextField("Title", text: $newRecipeTitle)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    showSaveRecipeName = false
                    newRecipeTitle = ""
                }
                Button("Save") {
                    persistNewRecipe(title: newRecipeTitle)
                }
                .buttonStyle(.borderedProminent)
                .disabled(newRecipeTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(28)
        .frame(width: 420)
        .background(Color.white)
    }

    private func confirmLine(_ label: String, _ value: String, icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.45, green: 0.49, blue: 0.55))
                Text(value)
                    .font(.system(size: 13))
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(Color(red: 0.15, green: 0.42, blue: 0.95))
        }
    }

    private func cardTitle(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color(red: 0.12, green: 0.14, blue: 0.20))
            .labelStyle(.titleAndIcon)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(red: 0.45, green: 0.49, blue: 0.55))
    }

    private func huggingPicker(selection: Binding<String>, options: [(id: String, title: String)]) -> some View {
        let currentTitle = options.first(where: { $0.id == selection.wrappedValue })?.title ?? ""

        return Menu {
            ForEach(options, id: \.id) { option in
                Button(option.title) {
                    selection.wrappedValue = option.id
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(currentTitle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .menuIndicator(.hidden)
        .buttonStyle(.bordered)
        .controlSize(.extraLarge)
    }

    private func nativePicker(selection: Binding<String>, options: [(id: String, title: String)]) -> some View {
        let currentTitle = options.first(where: { $0.id == selection.wrappedValue })?.title ?? ""

        return wideSystemButton {
            Menu {
                ForEach(options, id: \.id) { option in
                    Button(option.title) {
                        selection.wrappedValue = option.id
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(currentTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuIndicator(.hidden)
        }
    }

    private func lockedField(text: String, icon: String) -> some View {
        wideSystemButton {
            Button {} label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                    Text(text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(true)
        }
    }

    private func wideSystemButton<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let inner = content()
        return GeometryReader { geo in
            inner
                .buttonStyle(.bordered)
                .controlSize(.extraLarge)
                .frame(width: geo.size.width, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .leading)
    }

    private func mockCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(red: 0.90, green: 0.91, blue: 0.93), lineWidth: 1)
            )
    }

    private func copyErrorToClipboard(_ error: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(error, forType: .string)
        #endif
    }

    private func statusRow(text: String, ssh: Bool) -> some View {
        HStack(spacing: 6) {
            if ssh {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 0.45, green: 0.49, blue: 0.55))
            }
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.45, green: 0.49, blue: 0.55))
        }
        .accessibilityLabel(text)
    }

    private func replaceModeChoice(id: String, title: String, icon: String) -> some View {
        let isSelected = replaceMode == id

        return Button {
            replaceMode = id
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(
                            isSelected
                                ? Color(red: 0.15, green: 0.42, blue: 0.95)
                                : Color(red: 0.78, green: 0.81, blue: 0.85),
                            lineWidth: 1.5
                        )
                        .frame(width: 16, height: 16)
                    if isSelected {
                        Circle()
                            .fill(Color(red: 0.15, green: 0.42, blue: 0.95))
                            .frame(width: 8, height: 8)
                    }
                }
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                    .foregroundStyle(Color(red: 0.35, green: 0.40, blue: 0.48))
                Text(title)
                    .font(.system(size: 13))
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func operationChoice(id: String, title: String, icon: String) -> some View {
        let isSelected = strategy == id

        return Button {
            strategy = id
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(
                            isSelected
                                ? Color(red: 0.15, green: 0.42, blue: 0.95)
                                : Color(red: 0.78, green: 0.81, blue: 0.85),
                            lineWidth: 1.5
                        )
                        .frame(width: 16, height: 16)
                    if isSelected {
                        Circle()
                            .fill(Color(red: 0.15, green: 0.42, blue: 0.95))
                            .frame(width: 8, height: 8)
                    }
                }
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                    .foregroundStyle(Color(red: 0.35, green: 0.40, blue: 0.48))
                Text(title)
                    .font(.system(size: 13))
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView(model: AppModel())
        .frame(width: 980, height: 640)
        .preferredColorScheme(.light)
}
