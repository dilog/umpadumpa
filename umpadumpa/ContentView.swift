import SwiftUI

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
    @State private var sourceDatabase = "welcome_prod"
    @State private var destinationConnectionId = "localhost"
    @State private var destinationDatabase = "welcome"
    @State private var strategy = "backup"
    @State private var replaceMode = ReplaceMode.importInPlace.rawValue
    @State private var newDatabaseName = "welcome_fresh"
    @State private var backupName = "welcome_backup_20260918_1515"
    @State private var showSystemDatabases = false
    @State private var showConfirm = false
    @State private var tableScope = "all"
    @State private var selectedTableNames: Set<String> = []
    @State private var skipTableReset = false
    @State private var showSaveRecipeName = false
    @State private var newRecipeTitle = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            mainArea
        }
        .preferredColorScheme(.light)
        .background(Color.white)
        .frame(minWidth: 980, minHeight: 720)
        .sheet(isPresented: $showConfirm) {
            confirmSheet
                .preferredColorScheme(.light)
        }
        .sheet(isPresented: $model.showNewConnection) {
            newConnectionSheet
                .preferredColorScheme(.light)
        }
        .sheet(isPresented: $showSaveRecipeName) {
            saveRecipeNameSheet
                .preferredColorScheme(.light)
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
            }
        }
        .onChange(of: sourceDatabase) { _, _ in
            if skipTableReset {
                skipTableReset = false
                return
            }
            tableScope = "all"
            selectedTableNames = []
        }
        .onChange(of: destinationConnectionId) { _, id in
            if prototypeConnections.contains(where: { $0.id == id }) == false {
                // real connections use typed database names
            } else if let connection = prototypeConnections.first(where: { $0.id == id }) {
                let names = visibleDatabases(for: connection)
                if names.contains(destinationDatabase) == false {
                    destinationDatabase = connection.databases.first ?? destinationDatabase
                }
            }
        }
        .onChange(of: destinationDatabase) { _, name in
            backupName = BackupName.defaultName(database: name, at: Date())
        }
        .onChange(of: tableScope) { _, scope in
            if scope == "choose" {
                replaceMode = ReplaceMode.importInPlace.rawValue
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

    private func visibleDatabases(for connection: FakeConnection) -> [String] {
        if showSystemDatabases {
            return connection.databases + connection.systemDatabases
        }
        return connection.databases
    }

    private var strategyLabel: String {
        if strategy == "replace" { return "Replace" }
        if strategy == "create" { return "Create new" }
        return "Backup and replace"
    }

    private var tablesForSourceDatabase: [String] {
        if sourceDatabase == "analytics" {
            return ["events", "sessions", "funnels"]
        }
        if sourceDatabase == "voila" {
            return ["clients", "payments", "invoices"]
        }
        return ["users", "orders", "bookings", "invoices", "rooms", "permissions", "guests", "rates", "availability", "messages", "files", "logs"]
    }

    private var tablesSummary: String {
        if tableScope == "all" {
            return "All tables"
        }
        let names = tablesForSourceDatabase.filter { selectedTableNames.contains($0) }
        if names.isEmpty {
            return "No tables selected"
        }
        return names.joined(separator: ", ")
    }

    private var pullDestinationName: String {
        strategy == "create" ? newDatabaseName : destinationDatabase
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            appLogo
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 18)

            ForEach(model.connections) { connection in
                sidebarButton(
                    id: connection.id.uuidString,
                    title: connection.name,
                    icon: connection.name.lowercased() == "localhost" ? "laptopcomputer" : "externaldrive.fill"
                )
            }

            Button {
                model.showNewConnection = true
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
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.20, green: 0.45, blue: 0.98))
                    .frame(width: 28, height: 28)
                Image(systemName: "cylinder.split.1x2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text("umpadumpa")
                .font(.system(size: 15, weight: .semibold))
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
        }
    }

    // MARK: - Main

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
            Text("History")
                .font(.system(size: 28, weight: .bold))

            Table(model.history) {
                TableColumn("When") { row in
                    Text(row.when.formatted(date: .abbreviated, time: .shortened))
                }
                .width(min: 110, ideal: 140)

                TableColumn("Source") { row in
                    Text(row.source)
                }

                TableColumn("Destination") { row in
                    Text(row.destination)
                }

                TableColumn("Result") { row in
                    Label(
                        row.succeeded ? "OK" : "Failed",
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
            if let error = model.pullError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.90, green: 0.30, blue: 0.30))
            }
            footerBar
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
        .padding(.top, 16)
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

        if destName.isEmpty || sourceDatabase.isEmpty {
            return nil
        }

        let chosenTables = tablesForSourceDatabase.filter { selectedTableNames.contains($0) }
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
    }

    private func originColumn(for connection: Connection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("Source", icon: "icloud")

            fieldLabel("Connection")
            lockedField(text: connection.name, icon: "lock.fill")

            fieldLabel("Database")
            TextField("Database", text: $sourceDatabase)
                .textFieldStyle(.roundedBorder)
                .controlSize(.extraLarge)

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
                        selectedTableNames = Set(tablesForSourceDatabase)
                    }
                    Button("Uncheck all") {
                        selectedTableNames = []
                    }
                }
                .font(.system(size: 12))
                .buttonStyle(.plain)
                .foregroundStyle(Color(red: 0.15, green: 0.42, blue: 0.95))

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(tablesForSourceDatabase, id: \.self) { tableName in
                            Toggle(tableName, isOn: tableBinding(tableName))
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

            fieldLabel("Database")
            TextField("Database", text: $destinationDatabase)
                .textFieldStyle(.roundedBorder)
                .controlSize(.extraLarge)

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
                        persistSelectedRecipe()
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
                    Label("Start dump", systemImage: "arrow.down.circle.fill")
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

        if destName.isEmpty {
            return nil
        }

        let chosenTables = tablesForSourceDatabase.filter { selectedTableNames.contains($0) }
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
            backupName: strategy == "backup" ? backupName : ""
        )
    }

    private func runPullFromConfirm() {
        guard let request = currentPullRequest() else {
            return
        }
        let summary = model.engine.confirm(request)
        showConfirm = false
        model.isPulling = true
        Task {
            defer { model.isPulling = false }
            do {
                _ = try await model.engine.run(summary)
                model.pullError = nil
                model.refreshHistory()
            } catch PullError.alreadyRunning {
                model.pullError = "A Pull is already running."
                model.refreshHistory()
            } catch PullError.dumpFailed {
                model.pullError = "Dump failed. Destination was not changed."
                model.refreshHistory()
            } catch PullError.tunnelFailed {
                model.pullError = "SSH tunnel failed. Destination was not changed."
                model.refreshHistory()
            } catch PullError.missingClient(.mysqldump) {
                model.pullError = "mysqldump was not found. Set its path in Settings."
                model.refreshHistory()
            } catch PullError.missingClient(.mysql) {
                model.pullError = "mysql was not found. Set its path in Settings."
                model.refreshHistory()
            } catch PullError.nameAlreadyExists {
                model.pullError = "That name already exists. The destination was not changed."
                model.refreshHistory()
            } catch PullError.importFailed {
                model.pullError = "Import failed."
                model.refreshHistory()
            } catch {
                model.pullError = "Pull failed."
                model.refreshHistory()
            }
        }
    }

    private var newConnectionSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Connection")
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
                Spacer()
                Button("Cancel") { model.showNewConnection = false }
                Button("Save") {
                    let connection = model.addConnection()
                    selectNav(connection.id.uuidString)
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

    private func statusRow(text: String, ssh: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(red: 0.22, green: 0.78, blue: 0.40))
                .frame(width: 7, height: 7)
            if ssh {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 0.45, green: 0.49, blue: 0.55))
            }
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.45, green: 0.49, blue: 0.55))
        }
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
