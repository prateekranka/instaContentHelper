import Foundation

enum MiraLocation: Equatable {
    case editor(UUID), todayCards(UUID), words(UUID), filming(UUID), done(UUID)

    init(_ route: MiraRoute) {
        switch route {
        case .project(let id): self = .editor(id)
        case .todayCards(let id): self = .todayCards(id)
        case .words(let id): self = .words(id)
        case .shooting(let id): self = .filming(id)
        case .done(let id): self = .done(id)
        }
    }

    var route: MiraRoute {
        switch self {
        case .editor(let id): .project(id)
        case .todayCards(let id): .todayCards(id)
        case .words(let id): .words(id)
        case .filming(let id): .shooting(id)
        case .done(let id): .done(id)
        }
    }

    var projectID: UUID { route.projectID }

    func screen(in project: MiraProject, remembering previous: MiraProjectScreen?) -> MiraProjectScreen {
        switch self {
        case .editor: project.editorScreen(remembering: previous)
        case .todayCards: .todayCards
        case .words: .words
        case .filming, .done: .shooting
        }
    }
}

struct MiraLocationHistory {
    var paths: [MiraTab: [MiraLocation]] = [:]
    var screens: [UUID: MiraProjectScreen] = [:]
    var lastProject: UUID?
}

enum MiraLocationEvent {
    case selectTab(MiraTab)
    case setPath(MiraTab, [MiraRoute])
    case open(MiraTab, [MiraRoute])
    case push(MiraLocation)
    case showWords(UUID)
    case remember(UUID, MiraProjectScreen?, makeCurrent: Bool)
    case remove(UUID)
}

enum MiraLocationState {
    case today(MiraLocationHistory), projects(MiraLocationHistory)

    init(document: MiraDocument) {
        let saved = document.restoredNavigation()
        var history = MiraLocationHistory(
            paths: [.today: saved.today.map(MiraLocation.init), .projects: saved.projects.map(MiraLocation.init)],
            screens: Dictionary(document.projects.compactMap { project in
                project.lastScreen.map { (project.id, $0) }
            }, uniquingKeysWith: { first, _ in first }),
            lastProject: document.position.projectID)
        if let id = history.lastProject, history.screens[id] == nil {
            history.screens[id] = MiraProjectScreen(rawValue: document.position.screen)
        }
        self = saved.tab == .today ? .today(history) : .projects(history)
        if let location = current, let project = document.projects.first(where: { $0.id == location.projectID }) {
            self = handle(.remember(project.id, location.screen(in: project, remembering: history.screens[project.id]),
                                    makeCurrent: true))
        }
    }

    var tab: MiraTab {
        switch self {
        case .today: .today
        case .projects: .projects
        }
    }

    private var history: MiraLocationHistory {
        switch self {
        case .today(let history), .projects(let history): history
        }
    }

    var current: MiraLocation? { history.paths[tab]?.last }
    var lastProject: UUID? { history.lastProject }
    func rememberedScreen(_ id: UUID) -> MiraProjectScreen? { history.screens[id] }
    func path(_ tab: MiraTab) -> [MiraRoute] { history.paths[tab, default: []].map(\.route) }

    var nextAction: MiraNextAction? {
        switch current {
        case .editor: .reviewPlan
        case .todayCards: .makeCard
        case .words: .approveWords
        case .filming: .continueFilming
        case .done, nil: nil
        }
    }

    func handle(_ event: MiraLocationEvent) -> Self {
        var history = history
        var selected = tab
        switch event {
        case .selectTab(let tab):
            selected = tab
        case .setPath(let tab, let path):
            history.paths[tab] = path.map(MiraLocation.init)
        case .open(let tab, let path):
            history.paths[tab] = path.map(MiraLocation.init)
            selected = tab
        case .push(let location):
            if history.paths[tab]?.last != location { history.paths[tab, default: []].append(location) }
        case .showWords(let id):
            while let last = history.paths[tab]?.last, last == .filming(id) || last == .done(id) {
                history.paths[tab]?.removeLast()
            }
            if history.paths[tab]?.last != .words(id) { history.paths[tab, default: []].append(.words(id)) }
        case .remember(let id, let screen, let makeCurrent):
            history.screens[id] = screen
            if makeCurrent { history.lastProject = id }
        case .remove(let id):
            history.screens[id] = nil
            if history.lastProject == id { history.lastProject = nil }
            for tab in [MiraTab.today, .projects] { history.paths[tab]?.removeAll { $0.projectID == id } }
        }
        return selected == .today ? .today(history) : .projects(history)
    }
}
