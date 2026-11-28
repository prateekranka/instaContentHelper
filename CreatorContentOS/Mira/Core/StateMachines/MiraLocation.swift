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

enum MiraMainTab: Hashable, CaseIterable {
    case home, deals, myBrand
}

struct MiraLocationHistory {
    var savedTab: MiraTab = .today
    var paths: [MiraMainTab: [MiraLocation]] = [:]
    var screens: [MiraMainTab: [UUID: MiraProjectScreen]] = [:]
    var lastProject: UUID?
}

enum MiraLocationEvent {
    case selectTab(MiraMainTab)
    case setPath(MiraMainTab, [MiraRoute])
    case open(MiraMainTab, [MiraRoute], remembering: MiraProjectScreen? = nil)
    case push(MiraLocation)
    case showWords(UUID)
    case showPlan(UUID)
    case remember(UUID, MiraProjectScreen?, makeCurrent: Bool, tab: MiraMainTab? = nil)
    case remove(UUID)
}

enum MiraLocationState {
    case home(MiraLocationHistory), deals(MiraLocationHistory), myBrand(MiraLocationHistory)

    init(document: MiraDocument) {
        let saved = document.restoredNavigation()
        let activeTab: MiraMainTab = saved.tab == .today ? .home : .myBrand
        let paths: [MiraMainTab: [MiraLocation]] = [
            .home: saved.today.map(MiraLocation.init), .myBrand: saved.projects.map(MiraLocation.init),
        ]
        let projects = Dictionary(document.projects.compactMap { project in
            project.lastScreen.map { (project.id, $0) }
        }, uniquingKeysWith: { first, _ in first })
        var history = MiraLocationHistory(
            savedTab: saved.tab, paths: paths, screens: [.myBrand: projects], lastProject: document.position.projectID)
        if let id = history.lastProject, history.screens[activeTab]?[id] == nil,
            let screen = MiraProjectScreen(rawValue: document.position.screen) {
            history.screens[activeTab, default: [:]][id] = screen
        }
        for route in paths[.home, default: []] {
            if let project = document.projects.first(where: { $0.id == route.projectID }) {
                let previous = history.screens[.home]?[project.id]
                history.screens[.home, default: [:]][project.id] = route.screen(in: project, remembering: previous)
            }
        }
        self = saved.tab == .today ? .home(history) : .myBrand(history)
        if let location = current, let project = document.projects.first(where: { $0.id == location.projectID }) {
            self = handle(.remember(project.id, location.screen(in: project, remembering: rememberedScreen(project.id)),
                                    makeCurrent: true))
        }
    }

    var tab: MiraMainTab {
        switch self {
        case .home: .home
        case .deals: .deals
        case .myBrand: .myBrand
        }
    }

    private var history: MiraLocationHistory {
        switch self {
        case .home(let history), .deals(let history), .myBrand(let history): history
        }
    }

    var savedTab: MiraTab { history.savedTab }
    var current: MiraLocation? { history.paths[tab]?.last }
    var lastProject: UUID? { history.lastProject }
    func rememberedScreen(_ id: UUID, in tab: MiraMainTab? = nil) -> MiraProjectScreen? {
        history.screens[tab ?? self.tab]?[id]
    }

    func path(_ tab: MiraMainTab) -> [MiraRoute] { history.paths[tab, default: []].map(\.route) }

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
        case .open(let tab, let path, let screen):
            history.paths[tab] = path.map(MiraLocation.init)
            if let screen, let id = path.last?.projectID {
                history.screens[tab, default: [:]][id] = screen
            }
            selected = tab
        case .push(let location):
            if history.paths[tab]?.last != location { history.paths[tab, default: []].append(location) }
        case .showWords(let id):
            while let last = history.paths[tab]?.last, last == .filming(id) || last == .done(id) {
                history.paths[tab]?.removeLast()
            }
            if history.paths[tab]?.last != .words(id) { history.paths[tab, default: []].append(.words(id)) }
        case .showPlan(let id):
            var path = history.paths[tab, default: []]
            if path.last == .words(id), path.dropLast().last == .editor(id) { path.removeLast() }
            if path.last != .editor(id) { path.append(.editor(id)) }
            history.paths[tab] = path
            history.screens[tab, default: [:]][id] = .shots
        case .remember(let id, let screen, let makeCurrent, let owner):
            let owner = owner ?? tab
            history.screens[owner, default: [:]][id] = screen
            if makeCurrent && owner == tab { history.lastProject = id }
        case .remove(let id):
            if history.lastProject == id { history.lastProject = nil }
            for tab in MiraMainTab.allCases {
                history.screens[tab]?[id] = nil
                history.paths[tab]?.removeAll { $0.projectID == id }
            }
        }
        switch selected {
        case .home:
            history.savedTab = .today
            return .home(history)
        case .deals:
            return .deals(history)
        case .myBrand:
            history.savedTab = .projects
            return .myBrand(history)
        }
    }
}
