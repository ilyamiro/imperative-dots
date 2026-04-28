import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window
    focus: true

    Scaler {
        id: scaler
        currentWidth: Screen.width
    }

    function s(val) { 
        return scaler.s(val); 
    }

    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color crust: _theme.crust
    readonly property color mantle: _theme.mantle
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color mauve: _theme.mauve || "#cba6f7"
    readonly property color blue: _theme.blue || "#89b4fa"
    readonly property color green: _theme.green || "#a6e3a1"
    readonly property color red: _theme.red || "#f38ba8"

    // --- STATE MANAGEMENT ---
    property string currentView: "search" // "search" or "series"
    property string mediaType: "movie" // "movie" or "tv"
    property string filterSort: "Default"
    property bool isSearching: searchInput.text.trim() !== ""
    property bool isSearchingNetwork: false
    property bool isSearchMode: window.isSearching
    property string selectedImdbId: ""
    property string selectedTitle: ""
    property string selectedPoster: ""
    property string selectedDescription: ""
    property var seriesDataMap: ({})
    property int currentSeason: 1
    property bool isLoadingSeries: false
    property bool trendingMoviesLoaded: false
    property bool trendingTvLoaded: false
    property bool isFetchingMovies: false
    property bool isFetchingTv: false
    property bool isLoadingPopular: isFetchingMovies || isFetchingTv
    property var currentFetchResults: []
    property var rawTrendingMovies: []
    property var rawTrendingTv: []
    property real trendingMoviesLastFetch: 0
    property real trendingTvLastFetch: 0
    readonly property real trendingCacheMaxAge: 12 * 60 * 60 * 1000
    property bool seasonSwitching: false
    property bool stateRestored: false
    property bool pendingSeriesFocusRestore: false

    Timer {
        id: safetyLoadingTimer
        interval: 12000
        running: window.isLoadingPopular || window.isSearchingNetwork
        repeat: false
        onTriggered: {
            window.isFetchingMovies = false
            window.isFetchingTv = false
            window.isSearchingNetwork = false
        }
    }

    Timer {
        id: searchDebounceTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (searchInput.text.trim() !== "") {
                doSearch(searchInput.text)
            }
        }
    }

    Timer {
        id: seriesFocusRestoreTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (window.currentView === "series" && !window.isSourceModalOpen) {
                window.forceActiveFocus()
                window.pendingSeriesFocusRestore = false
            }
        }
    }

    // --- SHARED DISK I/O HELPER ---
    function saveJsonToCache(filename, dataObj) {
        let jsStr = JSON.stringify(dataObj).replace(/'/g, "'\\''")
        Quickshell.execDetached(["bash", "-c", "mkdir -p ~/.cache && echo '" + jsStr + "' > ~/.cache/" + filename])
    }

    // --- PERSISTENT CACHE IO ---
    Process {
        id: readHistoryProc
        command: ["bash", "-c", "cat ~/.cache/qs_movie_history.json 2>/dev/null || echo '[]'"]
        running: false
        stdout: SplitParser {
            onRead: (data) => {
                try {
                    let parsed = JSON.parse(data.trim())
                    searchHistoryModel.clear()
                    for (let i = parsed.length - 1; i >= 0; i--) {
                        searchHistoryModel.insert(0, { query: parsed[i] })
                    }
                } catch(e) {}
            }
        }
    }

    Process {
        id: readWatchHistoryProc
        command: ["bash", "-c", "cat ~/.cache/qs_movie_watch_history.json 2>/dev/null || echo '[]'"]
        running: false
        stdout: SplitParser {
            onRead: (data) => {
                try {
                    let parsed = JSON.parse(data.trim())
                    watchHistoryModel.clear()
                    for (let i = parsed.length - 1; i >= 0; i--) {
                        watchHistoryModel.insert(0, parsed[i])
                    }
                } catch(e) {}
            }
        }
    }

    function processTrendingCache(parsed, typeStr, targetModel) {
        let now = Date.now()
        let isMovie = typeStr === "movie"
        let lastFetch = parsed[isMovie ? "moviesLastFetch" : "tvLastFetch"] || 0
        let items = parsed[isMovie ? "movies" : "tv"]

        if (items && items.length > 0) {
            targetModel.clear()
            if (isMovie) window.rawTrendingMovies = items; else window.rawTrendingTv = items
            for (let i = 0; i < items.length; i++) targetModel.append(items[i])
            
            if (isMovie) { window.trendingMoviesLoaded = true; window.isFetchingMovies = false; window.trendingMoviesLastFetch = lastFetch } 
            else { window.trendingTvLoaded = true; window.isFetchingTv = false; window.trendingTvLastFetch = lastFetch }
            
            if ((now - lastFetch) > window.trendingCacheMaxAge) fetchTrending(typeStr === "movie" ? "movie" : "series")
        } else {
            fetchTrending(typeStr === "movie" ? "movie" : "series")
        }
    }

    Process {
        id: readTrendingCacheProc
        command: ["bash", "-c", "cat ~/.cache/qs_trending_cache.json 2>/dev/null || echo '{}'"]
        running: false
        stdout: SplitParser {
            onRead: (data) => {
                try {
                    let parsed = JSON.parse(data.trim())
                    processTrendingCache(parsed, "movie", cachedTrendingMovies)
                    processTrendingCache(parsed, "tv", cachedTrendingTv)
                } catch(e) {
                    fetchTrending("movie")
                    fetchTrending("series")
                }
            }
        }
    }

    Process {
        id: readUiStateProc
        command: ["bash", "-c", "cat ~/.cache/qs_ui_state.json 2>/dev/null || echo '{}'"]
        running: false
        stdout: SplitParser {
            onRead: (data) => {
                try {
                    let s = JSON.parse(data.trim())
                    if (!s || Object.keys(s).length === 0) {
                        window.stateRestored = true
                        return
                    }
                    if (s.mediaType) window.mediaType = s.mediaType
                    if (s.filterSort) {
                        window.filterSort = s.filterSort
                        let idx = filterSelector.model.indexOf(s.filterSort)
                        if (idx >= 0) filterSelector.currentIndex = idx
                    }
                    if (s.searchText && s.searchText !== "") searchInput.text = s.searchText
                    if (s.currentView) window.currentView = s.currentView
                    if (s.selectedImdbId) window.selectedImdbId = s.selectedImdbId
                    if (s.selectedTitle) window.selectedTitle = s.selectedTitle
                    if (s.selectedPoster) window.selectedPoster = s.selectedPoster
                    if (s.selectedDescription) window.selectedDescription = s.selectedDescription
                    if (s.currentSeason) window.currentSeason = s.currentSeason
                    
                    if (s.isSourceModalOpen && s.pendingMedia && s.pendingMedia.imdbId) {
                        window.pendingMedia = s.pendingMedia
                        window.foundSourceName = s.foundSourceName || ""
                        for (let i = 0; i < sourceModel.count; i++) sourceModel.setProperty(i, "status", "pending")
                        window.isSourceModalOpen = true
                        if (s.checkingState === "found" && s.foundSourceName) {
                            window.checkingState = "found"
                            for (let i = 0; i < sourceModel.count; i++) {
                                if (sourceModel.get(i).name === s.foundSourceName) {
                                    sourceModel.setProperty(i, "status", "success")
                                    window.currentCheckIndex = i
                                    break
                                }
                            }
                        } else {
                            window.sourceCheckOrder = buildSourceOrder()
                            window.sourceCheckStep = 0
                            window.currentCheckIndex = window.sourceCheckOrder[0]
                            window.checkingState = "checking"
                            checkNextSource()
                        }
                    }
                    if (s.currentView === "series" && s.selectedImdbId) {
                        window.pendingSeriesFocusRestore = true
                        fetchSeriesData(s.selectedImdbId, s.currentSeason || 1, "", "", true)
                    }
                    window.stateRestored = true
                } catch(e) {
                    window.stateRestored = true
                }
            }
        }
    }

    property var sourcePrefs: ({})
    Process {
        id: readSourcePrefsProc
        command: ["bash", "-c", "cat ~/.cache/qs_source_prefs.json 2>/dev/null || echo '{}'"]
        running: false
        stdout: SplitParser {
            onRead: (data) => {
                try { window.sourcePrefs = JSON.parse(data.trim()) } 
                catch(e) { window.sourcePrefs = {} }
            }
        }
    }

    // --- SAVING CACHE FUNCTIONS ---
    function saveUiState() {
        saveJsonToCache("qs_ui_state.json", {
            mediaType: window.mediaType, filterSort: window.filterSort, searchText: searchInput.text,
            currentView: window.currentView, selectedImdbId: window.selectedImdbId,
            selectedTitle: window.selectedTitle, selectedPoster: window.selectedPoster,
            selectedDescription: window.selectedDescription, currentSeason: window.currentSeason,
            isSourceModalOpen: window.isSourceModalOpen, checkingState: window.checkingState,
            pendingMedia: window.pendingMedia, foundSourceName: window.foundSourceName
        })
    }

    function saveHistory() {
        let arr = []
        for (let i = 0; i < searchHistoryModel.count; i++) arr.push(searchHistoryModel.get(i).query)
        saveJsonToCache("qs_movie_history.json", arr)
    }

    function saveWatchHistory() {
        let arr = []
        for (let i = 0; i < watchHistoryModel.count; i++) {
            let item = watchHistoryModel.get(i)
            arr.push({ imdbId: item.imdbId, title: item.title, poster: item.poster, type: item.type })
        }
        saveJsonToCache("qs_movie_watch_history.json", arr)
    }

    function saveTrendingCache() {
        if (cachedTrendingMovies.count === 0 || cachedTrendingTv.count === 0) return
        let cacheObj = { moviesLastFetch: window.trendingMoviesLastFetch, tvLastFetch: window.trendingTvLastFetch, movies: [], tv: [] }
        for (let i = 0; i < cachedTrendingMovies.count; i++) {
            let m = cachedTrendingMovies.get(i)
            cacheObj.movies.push({ imdbId: m.imdbId, title: m.title, poster: m.poster, type: m.type, year: m.year, rating: m.rating || 0, popularity: i })
        }
        for (let i = 0; i < cachedTrendingTv.count; i++) {
            let t = cachedTrendingTv.get(i)
            cacheObj.tv.push({ imdbId: t.imdbId, title: t.title, poster: t.poster, type: t.type, year: t.year, rating: t.rating || 0, popularity: i })
        }
        saveJsonToCache("qs_trending_cache.json", cacheObj)
    }

    function saveSourcePref(imdbId, sourceName) {
        let prefs = window.sourcePrefs
        prefs[imdbId] = sourceName
        window.sourcePrefs = prefs
        saveJsonToCache("qs_source_prefs.json", prefs)
    }

    // --- SOURCE MODEL ---
    ListModel {
        id: sourceModel
        ListElement { name: "VidSrc.net";    urlMovie: "https://vidsrc.net/embed/movie/%1";                               urlTv: "https://vidsrc.net/embed/tv/%1/%2/%3";                            status: "pending" }
        ListElement { name: "VidLink";       urlMovie: "https://vidlink.pro/movie/%1?autoplay=1";                         urlTv: "https://vidlink.pro/tv/%1/%2/%3?autoplay=1";                      status: "pending" }
        ListElement { name: "VidSrc.pro";    urlMovie: "https://vidsrc.pro/embed/movie/%1";                               urlTv: "https://vidsrc.pro/embed/tv/%1/%2/%3";                            status: "pending" }
        ListElement { name: "VidSrc.in";     urlMovie: "https://vidsrc.in/embed/movie/%1";                                urlTv: "https://vidsrc.in/embed/tv/%1/%2/%3";                             status: "pending" }
        ListElement { name: "VidSrc.cc";     urlMovie: "https://vidsrc.cc/v2/embed/movie/%1?autoPlay=true";               urlTv: "https://vidsrc.cc/v2/embed/tv/%1/%2/%3?autoPlay=true";            status: "pending" }
        ListElement { name: "Embed.su";      urlMovie: "https://embed.su/embed/movie/%1";                                 urlTv: "https://embed.su/embed/tv/%1/%2/%3";                              status: "pending" }
        ListElement { name: "SmashyStream";  urlMovie: "https://player.smashy.stream/movie/%1";                           urlTv: "https://player.smashy.stream/tv/%1?s=%2&e=%3";                    status: "pending" }
        ListElement { name: "AutoEmbed";     urlMovie: "https://autoembed.to/movie/imdb/%1";                              urlTv: "https://autoembed.to/tv/imdb/%1-%2-%3";                           status: "pending" }
        ListElement { name: "2Embed";        urlMovie: "https://www.2embed.cc/embed/%1";                                  urlTv: "https://www.2embed.cc/embedtv/%1&s=%2&e=%3";                      status: "pending" }
        ListElement { name: "MultiEmbed";    urlMovie: "https://multiembed.mov/directstream.php?video_id=%1";             urlTv: "https://multiembed.mov/directstream.php?video_id=%1&s=%2&e=%3";  status: "pending" }
    }

    // --- ANIMATIONS & FOCUS ---
    property real introPhase: 0
    NumberAnimation on introPhase {
        id: introPhaseAnim
        from: 0; to: 1; duration: 800; easing.type: Easing.OutQuart; running: true
    }

    Timer {
        id: focusTimer
        interval: 50; running: true; repeat: false
        onTriggered: {
            if (window.currentView === "search") searchInput.forceActiveFocus()
            else window.forceActiveFocus()
        }
    }

    Timer {
        id: scrollToTopTimer
        interval: 80; running: false; repeat: false
        onTriggered: {
            movieGrid.positionViewAtBeginning()
            tvGrid.positionViewAtBeginning()
            searchGrid.positionViewAtBeginning()
        }
    }

    Component.onCompleted: {
        readHistoryProc.running = true
        readWatchHistoryProc.running = true
        readSourcePrefsProc.running = true
        window.isFetchingMovies = true
        window.isFetchingTv = true
        readTrendingCacheProc.running = true
        readUiStateProc.running = true
    }

    Connections {
        target: window
        function onVisibleChanged() {
            if (window.visible) {
                introPhaseAnim.restart()
                if (!window.isSourceModalOpen && window.currentView === "search") {
                    focusTimer.restart()
                    scrollToTopTimer.restart()
                } else if (window.currentView === "series") {
                    seriesFocusRestoreTimer.restart()
                }
                if (searchHistoryModel.count === 0) readHistoryProc.running = true
                if (watchHistoryModel.count === 0) readWatchHistoryProc.running = true
                if (!window.trendingMoviesLoaded) fetchTrending("movie")
                if (!window.trendingTvLoaded) fetchTrending("series")
                if (searchInput.text !== "") doSearch(searchInput.text)
                if (window.currentView === "series" && window.selectedImdbId !== "" && episodeModel.count === 0) {
                    fetchSeriesData(window.selectedImdbId, window.currentSeason, "", "", true)
                }
            } else {
                saveUiState()
            }
        }
    }

    Keys.onPressed: (event) => {
        if (window.isSourceModalOpen) {
            if (event.key === Qt.Key_Escape) { window.closeSourceModal(); event.accepted = true }
        } else if (window.currentView === "series") {
            if (event.key === Qt.Key_Escape) {
                window.currentView = "search"
                searchInput.forceActiveFocus()
                event.accepted = true
            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                let sCount = seasonModel.count
                if (sCount > 0) {
                    let idx = -1
                    for (let i = 0; i < sCount; i++) { if (seasonModel.get(i).seasonNum === window.currentSeason) { idx = i; break } }
                    if (idx !== -1) {
                        let step = event.key === Qt.Key_Tab ? 1 : -1
                        window.currentSeason = seasonModel.get((idx + step + sCount) % sCount).seasonNum
                        updateEpisodes(window.currentSeason)
                    }
                }
                event.accepted = true
            } else if (event.key === Qt.Key_Down) {
                if (epList.currentIndex < epList.count - 1) epList.currentIndex++; event.accepted = true
            } else if (event.key === Qt.Key_Up) {
                if (epList.currentIndex > 0) epList.currentIndex--; event.accepted = true
            } else if (event.key === Qt.Key_Return) {
                let ep = episodeModel.get(epList.currentIndex)
                if (ep) startSourceCheck("tv", window.selectedImdbId, window.selectedTitle, window.selectedPoster, window.currentSeason, ep.epNum)
                event.accepted = true
            }
        } else if (event.key === Qt.Key_Escape) {
            saveUiState()
            Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"])
            event.accepted = true
        }
    }

    property bool isKeyboardNav: false
    Timer { id: keyboardNavTimer; interval: 500; repeat: false; onTriggered: window.isKeyboardNav = false }

    ListModel { id: searchHistoryModel }
    ListModel { id: watchHistoryModel }
    ListModel { id: cachedTrendingMovies }
    ListModel { id: cachedTrendingTv }
    ListModel { id: searchResults }
    ListModel { id: seasonModel }
    ListModel { id: episodeModel }

    function addToWatchHistory(item) {
        for (let i = 0; i < watchHistoryModel.count; i++) {
            if (watchHistoryModel.get(i).imdbId === item.imdbId) {
                watchHistoryModel.remove(i)
                break
            }
        }
        watchHistoryModel.insert(0, item)
        if (watchHistoryModel.count > 15) watchHistoryModel.remove(15)
        saveWatchHistory()
    }

    function addSearchHistory(query) {
        if (query.trim() === "") return
        for (let i = 0; i < searchHistoryModel.count; i++) {
            if (searchHistoryModel.get(i).query.toLowerCase() === query.toLowerCase()) {
                searchHistoryModel.remove(i)
                break
            }
        }
        searchHistoryModel.insert(0, { query: query.trim() })
        if (searchHistoryModel.count > 10) searchHistoryModel.remove(10)
        saveHistory()
    }

    // ==========================================
    // SOURCE CHECKING SYSTEM
    // ==========================================
    property bool isSourceModalOpen: false
    property int currentCheckIndex: 0
    property var pendingMedia: ({})
    property string checkingState: "idle"
    property string foundSourceName: ""
    property var activeCheckXhr: null
    readonly property var errorPagePatterns: [
        "404", "not found", "no results", "video not found", "media not found",
        "content not found", "page not found", "error 404", "does not exist"
    ]

    function buildSourceUrl(srcIndex) {
        let src = sourceModel.get(srcIndex)
        let m = pendingMedia
        if (m.type === "movie") return src.urlMovie.arg(m.imdbId)
        return src.urlTv.arg(m.imdbId).arg(m.season).arg(m.ep)
    }

    function buildSourceOrder() {
        let order = []
        let imdbId = pendingMedia.imdbId
        let preferred = window.sourcePrefs[imdbId] || null
        let prefIdx = -1
        if (preferred) {
            for (let i = 0; i < sourceModel.count; i++) {
                if (sourceModel.get(i).name === preferred) { prefIdx = i; break }
            }
        }
        if (prefIdx !== -1) order.push(prefIdx)
        for (let i = 0; i < sourceModel.count; i++) { if (i !== prefIdx) order.push(i) }
        return order
    }

    property var sourceCheckOrder: []
    property int sourceCheckStep: 0

    function startSourceCheck(type, imdbId, title, poster, season, ep) {
        pendingMedia = { type: type, imdbId: imdbId, title: title, poster: poster, season: season, ep: ep }
        for (let i = 0; i < sourceModel.count; i++) sourceModel.setProperty(i, "status", "pending")
        addToWatchHistory({ imdbId: imdbId, title: title, poster: poster, type: type })
        window.sourceCheckOrder = buildSourceOrder()
        window.sourceCheckStep = 0
        window.currentCheckIndex = window.sourceCheckOrder[0]
        window.foundSourceName = ""
        window.isSourceModalOpen = true
        window.checkingState = "checking"
        if (sourceListUI) sourceListUI.positionViewAtBeginning()
        checkNextSource()
        saveUiState()
    }

    function closeSourceModal() {
        if (window.activeCheckXhr !== null) {
            try { window.activeCheckXhr.abort() } catch(e) {}
            window.activeCheckXhr = null
        }
        window.isSourceModalOpen = false
        window.checkingState = "idle"
        if (window.currentView === "series") window.forceActiveFocus()
        else searchInput.forceActiveFocus()
        saveUiState()
    }

    function skipToNextSource() {
        if (window.activeCheckXhr !== null) {
            try { window.activeCheckXhr.abort() } catch(e) {}
            window.activeCheckXhr = null
        }
        sourceModel.setProperty(window.currentCheckIndex, "status", "failed")
        window.sourceCheckStep++
        if (window.sourceCheckStep < window.sourceCheckOrder.length) {
            window.currentCheckIndex = window.sourceCheckOrder[window.sourceCheckStep]
            window.checkingState = "checking"
            checkNextSource()
        } else {
            window.checkingState = "failed_all"
        }
    }

    function checkNextSource() {
        if (!window.isSourceModalOpen || window.checkingState !== "checking") return
        if (window.sourceCheckStep >= window.sourceCheckOrder.length) {
            window.checkingState = "failed_all"
            return
        }
        
        window.currentCheckIndex = window.sourceCheckOrder[window.sourceCheckStep]
        sourceModel.setProperty(window.currentCheckIndex, "status", "checking")
        if (sourceListUI) sourceListUI.positionViewAtIndex(window.currentCheckIndex, ListView.Contain)
        
        let idx = window.currentCheckIndex
        let step = window.sourceCheckStep
        let url = buildSourceUrl(idx)
        let xhr = new XMLHttpRequest()
        window.activeCheckXhr = xhr
        
        xhr.open("GET", url, true)
        xhr.timeout = 6000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || !window.isSourceModalOpen || window.checkingState !== "checking" || window.sourceCheckStep !== step) return
            window.activeCheckXhr = null
            let code = xhr.status
            let body = xhr.responseText ? xhr.responseText.toLowerCase() : ""
            
            if (code === 404 || code === 410) {
                sourceModel.setProperty(idx, "status", "failed")
                window.sourceCheckStep++
                checkNextSource()
                return
            }
            if (code === 200 && body.length < 3000) {
                let looksLikeError = false
                for (let i = 0; i < window.errorPagePatterns.length; i++) {
                    if (body.indexOf(window.errorPagePatterns[i]) !== -1) {
                        looksLikeError = true
                        break
                    }
                }
                if (looksLikeError) {
                    sourceModel.setProperty(idx, "status", "failed")
                    window.sourceCheckStep++
                    checkNextSource()
                    return
                }
            }
            let isLive = (code === 0) || (code >= 200 && code < 400) || code === 401 || code === 403
            if (isLive) {
                sourceModel.setProperty(idx, "status", "success")
                window.foundSourceName = sourceModel.get(idx).name
                window.checkingState = "found"
                saveUiState()
                Quickshell.execDetached(["xdg-open", url])
            } else {
                sourceModel.setProperty(idx, "status", "failed")
                window.sourceCheckStep++
                checkNextSource()
            }
        }
        xhr.ontimeout = function() {
            if (!window.isSourceModalOpen || window.checkingState !== "checking" || window.sourceCheckStep !== step) return
            window.activeCheckXhr = null
            sourceModel.setProperty(idx, "status", "failed")
            window.sourceCheckStep++
            checkNextSource()
        }
        xhr.onerror = function() {
            if (!window.isSourceModalOpen || window.checkingState !== "checking" || window.sourceCheckStep !== step) return
            window.activeCheckXhr = null
            sourceModel.setProperty(idx, "status", "success")
            window.foundSourceName = sourceModel.get(idx).name
            window.checkingState = "found"
            saveUiState()
            Quickshell.execDetached(["xdg-open", url])
        }
        xhr.send()
    }

    // --- DATA FETCHING & FILTERING ---
    function fetchTrending(typeStr) {
        let isMovie = typeStr === "movie"
        if (isMovie) window.isFetchingMovies = true; else window.isFetchingTv = true
        
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "https://v3-cinemeta.strem.io/catalog/" + typeStr + "/top.json")
        xhr.onerror = function() { if (isMovie) window.isFetchingMovies = false; else window.isFetchingTv = false }
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (isMovie) window.isFetchingMovies = false; else window.isFetchingTv = false
            if (xhr.status === 200) {
                try {
                    let res = JSON.parse(xhr.responseText)
                    if (res && res.metas) {
                        let rawItems = []
                        let targetModel = isMovie ? cachedTrendingMovies : cachedTrendingTv
                        targetModel.clear()
                        for (let i = 0; i < res.metas.length; i++) {
                            let item = res.metas[i]
                            if (!item.id || !item.poster) continue
                            let entry = {
                                imdbId: item.id,
                                title: item.name || "Unknown",
                                poster: item.poster || item.posterShape || item.background || item.logo || "",
                                type: isMovie ? "movie" : "tv",
                                year: item.releaseInfo || "N/A",
                                rating: item.imdbRating || 0,
                                popularity: i
                            }
                            rawItems.push(entry)
                            targetModel.append(entry)
                        }
                        if (isMovie) { window.rawTrendingMovies = rawItems; window.trendingMoviesLastFetch = Date.now(); window.trendingMoviesLoaded = true } 
                        else { window.rawTrendingTv = rawItems; window.trendingTvLastFetch = Date.now(); window.trendingTvLoaded = true }
                        saveTrendingCache()
                    }
                } catch(e) {}
            }
        }
        xhr.send()
    }

    function getSortValue(item, field) {
        if (field === "year") return parseInt(item.year || item.releaseInfo || 0) || 0
        if (field === "title") return (item.title || item.name || "").toString()
        if (field === "rating") return parseFloat(item.rating || item.imdbRating || 0) || 0
        return 0
    }

    function sortItems(items) {
        let mode = window.filterSort
        if (mode === "Year (Newest)") items.sort((a, b) => getSortValue(b, "year") - getSortValue(a, "year"))
        else if (mode === "Year (Oldest)") items.sort((a, b) => getSortValue(a, "year") - getSortValue(b, "year"))
        else if (mode === "Title (A-Z)") items.sort((a, b) => getSortValue(a, "title").localeCompare(getSortValue(b, "title")))
        else if (mode === "Title (Z-A)") items.sort((a, b) => getSortValue(b, "title").localeCompare(getSortValue(a, "title")))
        else if (mode === "Rating (Best)") items.sort((a, b) => getSortValue(b, "rating") - getSortValue(a, "rating"))
        else if (mode === "Rating (Worst)") items.sort((a, b) => getSortValue(a, "rating") - getSortValue(b, "rating"))
        return items
    }

    function applyFiltersToPopular() {
        let rawMovies = sortItems(window.rawTrendingMovies.slice())
        let rawTv = sortItems(window.rawTrendingTv.slice())
        cachedTrendingMovies.clear(); for (let i = 0; i < rawMovies.length; i++) cachedTrendingMovies.append(rawMovies[i])
        cachedTrendingTv.clear(); for (let i = 0; i < rawTv.length; i++) cachedTrendingTv.append(rawTv[i])
        movieGrid.positionViewAtBeginning()
        tvGrid.positionViewAtBeginning()
    }

    function applyFiltersAndPopulate() {
        window.isKeyboardNav = false
        searchResults.clear()
        let items = sortItems(window.currentFetchResults.slice())
        for (let i = 0; i < items.length; i++) {
            let item = items[i]
            if (!item.id) continue
            searchResults.append({
                imdbId: item.id, title: item.name || "Unknown", poster: item.poster || "",
                type: item.type === "series" ? "tv" : "movie", year: item.releaseInfo || "N/A", rating: item.imdbRating || 0
            })
        }
        Qt.callLater(function() {
            if (searchGrid && searchGrid.count > 0) searchGrid.currentIndex = 0
            if (movieGrid && movieGrid.count > 0) movieGrid.currentIndex = 0
            if (tvGrid && tvGrid.count > 0) tvGrid.currentIndex = 0
        })
    }

    function doSearch(query) {
        let q = encodeURIComponent(query.trim())
        let expectedType = window.mediaType
        let typeStr = expectedType === "movie" ? "movie" : "series"
        if (q === "") { searchResults.clear(); window.isSearchingNetwork = false; return }
        addSearchHistory(query)
        window.isSearchingNetwork = true
        searchResults.clear()
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "https://v3-cinemeta.strem.io/catalog/" + typeStr + "/top/search=" + q + ".json")
        xhr.onerror = function() { window.isSearchingNetwork = false }
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (window.mediaType === expectedType) {
                window.isSearchingNetwork = false
                if (xhr.status === 200) {
                    try {
                        let res = JSON.parse(xhr.responseText)
                        if (res && res.metas) {
                            window.currentFetchResults = res.metas
                            applyFiltersAndPopulate()
                            enrichSearchPosters(res.metas, typeStr)
                        }
                    } catch(e) {}
                }
            }
        }
        xhr.send()
    }

    function enrichSearchPosters(metas, typeStr) {
        for (let i = 0; i < metas.length; i++) {
            let item = metas[i]
            if (item.poster && item.poster !== "") continue
            let capturedImdbId = item.id
            ;(function(cImdbId) {
                var xhr2 = new XMLHttpRequest()
                xhr2.open("GET", "https://v3-cinemeta.strem.io/meta/" + typeStr + "/" + cImdbId + ".json")
                xhr2.onreadystatechange = function() {
                    if (xhr2.readyState !== XMLHttpRequest.DONE) return
                    if (xhr2.status === 200) {
                        try {
                            let res2 = JSON.parse(xhr2.responseText)
                            if (res2 && res2.meta) {
                                let poster = res2.meta.poster || res2.meta.background || ""
                                if (poster !== "") {
                                    for (let j = 0; j < searchResults.count; j++) {
                                        if (searchResults.get(j).imdbId === cImdbId) {
                                            searchResults.setProperty(j, "poster", poster)
                                            break
                                        }
                                    }
                                    return
                                }
                            }
                        } catch(e) {}
                    }
                    fetchPosterFallback(cImdbId, typeStr)
                }
                xhr2.send()
            })(capturedImdbId)
        }
    }

    function fetchPosterFallback(imdbId, typeStr) {
        let rpdbUrl = "https://api.ratingposterdb.com/imdb/poster-default/" + imdbId + ".jpg"
        var xhrCheck = new XMLHttpRequest()
        xhrCheck.open("HEAD", rpdbUrl, true)
        xhrCheck.timeout = 5000
        xhrCheck.onreadystatechange = function() {
            if (xhrCheck.readyState !== XMLHttpRequest.DONE) return
            if (xhrCheck.status === 200) {
                for (let j = 0; j < searchResults.count; j++) {
                    if (searchResults.get(j).imdbId === imdbId) {
                        searchResults.setProperty(j, "poster", rpdbUrl)
                        break
                    }
                }
            }
        }
        xhrCheck.onerror = function() { /* silently fail — delegate shows title fallback */ }
        xhrCheck.send()
    }

    function fetchAndUpdatePoster(imdbId, typeStr, targetModel) {
        var xhr = new XMLHttpRequest()
        let metaType = typeStr === "tv" ? "series" : "movie"
        xhr.open("GET", "https://v3-cinemeta.strem.io/meta/" + metaType + "/" + imdbId + ".json")
        xhr.timeout = 6000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            let posterFound = ""
            if (xhr.status === 200) {
                try {
                    let res = JSON.parse(xhr.responseText)
                    if (res && res.meta) posterFound = res.meta.poster || res.meta.background || ""
                } catch(e) {}
            }
            if (posterFound !== "") {
                for (let j = 0; j < targetModel.count; j++) {
                    if (targetModel.get(j).imdbId === imdbId) {
                        targetModel.setProperty(j, "poster", posterFound)
                        break
                    }
                }
            } else {
                fetchPosterFallback(imdbId, metaType)
            }
        }
        xhr.onerror = function() { fetchPosterFallback(imdbId, metaType) }
        xhr.send()
    }

    function fetchSeriesData(imdbId, targetSeason, title, poster, isReload) {
        if (!isReload) {
            window.selectedImdbId = imdbId
            window.selectedTitle = title
            window.selectedPoster = poster
            window.selectedDescription = ""
            window.currentView = "series"
            window.forceActiveFocus()
        }
        window.isLoadingSeries = true
        seasonModel.clear()
        episodeModel.clear()

        var xhr = new XMLHttpRequest()
        xhr.open("GET", "https://v3-cinemeta.strem.io/meta/series/" + imdbId + ".json")
        xhr.onerror = function() { 
            window.isLoadingSeries = false
            if (isReload && window.pendingSeriesFocusRestore) seriesFocusRestoreTimer.restart()
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            window.isLoadingSeries = false
            if (xhr.status === 200) {
                try {
                    var res = JSON.parse(xhr.responseText)
                    if (res && res.meta) {
                        if (!isReload || !window.selectedDescription) window.selectedDescription = res.meta.description || res.meta.synopsis || ""
                        if ((!window.selectedPoster || window.selectedPoster === "") && res.meta.poster) window.selectedPoster = res.meta.poster
                        
                        if (res.meta.videos) {
                            let seasonsMap = {}
                            for (let i = 0; i < res.meta.videos.length; i++) {
                                let v = res.meta.videos[i]
                                if (v.season === 0) continue
                                if (!seasonsMap[v.season]) seasonsMap[v.season] = []
                                let epTitle = v.name || v.title || null
                                if (epTitle && /^(episode\s*\d+|s\d+e\d+|ep\.?\s*\d+)$/i.test(epTitle.toLowerCase().trim())) epTitle = null
                                seasonsMap[v.season].push({
                                    ep: v.episode,
                                    title: epTitle || ("Episode " + v.episode),
                                    hasRealTitle: epTitle !== null
                                })
                            }
                            let seasonKeys = Object.keys(seasonsMap).map(Number).sort((a, b) => a - b)
                            for (let i = 0; i < seasonKeys.length; i++) seasonModel.append({ seasonNum: seasonKeys[i] })
                            window.seriesDataMap = seasonsMap
                            
                            let newTargetSeason = (isReload && seasonsMap[targetSeason]) ? targetSeason : (seasonKeys[0] || 1)
                            window.currentSeason = newTargetSeason
                            updateEpisodes(newTargetSeason)
                        }
                    }
                } catch(e) {}
            }
            if (isReload && window.pendingSeriesFocusRestore) seriesFocusRestoreTimer.restart()
            if (!isReload) saveUiState()
        }
        xhr.send()
    }

    function loadSeriesDetails(imdbId, title, poster) {
        fetchSeriesData(imdbId, 1, title, poster, false)
    }

    function updateEpisodes(seasonNum) {
        window.seasonSwitching = true
        seasonContentSwapTimer.targetSeason = seasonNum
        seasonContentSwapTimer.restart()
    }

    Timer {
        id: seasonContentSwapTimer
        property int targetSeason: 1
        interval: 220
        repeat: false
        onTriggered: {
            episodeModel.clear()
            let eps = window.seriesDataMap[targetSeason]
            if (eps) {
                eps.sort((a, b) => a.ep - b.ep)
                for (let i = 0; i < eps.length; i++) {
                    episodeModel.append({ epNum: eps[i].ep, epTitle: eps[i].title, hasRealTitle: eps[i].hasRealTitle || false })
                }
            }
            epList.currentIndex = 0
            epList.positionViewAtBeginning()
            seasonFadeInTimer.restart()
        }
    }

    Timer { id: seasonFadeInTimer; interval: 30; repeat: false; onTriggered: window.seasonSwitching = false }

    function getActiveGrid() {
        if (window.isSearchMode) return searchGrid
        if (window.mediaType === "movie") return movieGrid
        return tvGrid
    }

    // --- SHARED STYLES ---
    component CustomComboBox: ComboBox {
        id: control
        font.family: "JetBrains Mono"; font.pixelSize: window.s(14)
        delegate: ItemDelegate {
            width: control.width; height: window.s(36)
            contentItem: Text { text: modelData || model.name; color: window.text; font: control.font; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { color: control.highlightedIndex === index ? window.surface1 : "transparent"; radius: window.s(10) }
        }
        indicator: Canvas {
            id: canvas
            x: control.width - width - control.rightPadding; y: control.topPadding + (control.availableHeight - height) / 2
            width: 12; height: 8; contextType: "2d"
            Connections { target: control; function onPressedChanged() { canvas.requestPaint() } }
            onPaint: { var ctx = canvas.getContext("2d"); ctx.reset(); ctx.moveTo(0, 0); ctx.lineTo(width, 0); ctx.lineTo(width / 2, height); ctx.fillStyle = window.subtext0; ctx.fill() }
        }
        contentItem: Text { leftPadding: window.s(10); rightPadding: control.indicator.width + control.spacing; text: control.currentText; font: control.font; color: window.text; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
        background: Rectangle { implicitWidth: window.s(180); implicitHeight: window.s(36); color: window.surface0; border.color: control.activeFocus ? window.surface2 : window.surface1; border.width: control.visualFocus ? 2 : 1; radius: window.s(10) }
        popup: Popup {
            y: control.height + window.s(4); width: control.width; implicitHeight: contentItem.implicitHeight; padding: window.s(4)
            contentItem: ListView { clip: true; implicitHeight: contentHeight; model: control.popup.visible ? control.delegateModel : null; currentIndex: control.highlightedIndex; ScrollIndicator.vertical: ScrollIndicator { } }
            background: Rectangle { color: window.crust; border.color: window.surface1; radius: window.s(14) }
        }
    }

    component PosterDelegate: Rectangle {
        width: window.s(120); height: width * 1.5
        radius: window.s(10); color: window.crust; clip: true
        property bool isHovered: posterMouse.containsMouse
        Image {
            id: posterImg
            anchors.fill: parent
            source: model.poster !== "" ? model.poster : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            cache: true
            sourceSize.width: window.s(240)
            sourceSize.height: window.s(360)
            visible: status === Image.Ready
        }
        Rectangle {
            anchors.fill: parent
            color: window.surface0
            visible: model.poster === "" || posterImg.status === Image.Error || posterImg.status === Image.Null
            radius: window.s(10)
            Column {
                anchors.centerIn: parent
                width: parent.width - window.s(10)
                spacing: window.s(6)
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: model.type === "tv" ? "📺" : "🎬"
                    font.pixelSize: window.s(22)
                }
                Text {
                    width: parent.width
                    text: model.title || "Unknown"
                    color: window.subtext0
                    font.family: "JetBrains Mono"
                    font.pixelSize: window.s(11)
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    maximumLineCount: 4
                    elide: Text.ElideRight
                }
            }
        }
        Rectangle {
            anchors.fill: parent; radius: window.s(10)
            color: window.mediaType === "tv" ? window.blue : window.mauve
            opacity: parent.isHovered ? 0.3 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }
        MouseArea {
            id: posterMouse; anchors.fill: parent; hoverEnabled: true
            onClicked: {
                if (model.type === "movie") startSourceCheck("movie", model.imdbId, model.title, model.poster, 0, 0)
                else loadSeriesDetails(model.imdbId, model.title, model.poster)
            }
        }
    }

    Component {
        id: dashboardHeaderComp
        Item {
            width: GridView.view.width
            property bool hasSearch: searchHistoryModel.count > 0
            property bool hasWatch: watchHistoryModel.count > 0
            readonly property real searchSectionH: hasSearch ? (window.s(16) + window.s(12) + window.s(32) + window.s(28)) : 0
            readonly property real watchSectionH: hasWatch ? (window.s(16) + window.s(12) + window.s(200) + window.s(28)) : 0
            readonly property real popularLabelH: window.s(16) + window.s(16)
            height: searchSectionH + watchSectionH + popularLabelH
            Column {
                width: parent.width
                spacing: 0
                Item {
                    width: parent.width
                    height: parent.parent.searchSectionH
                    visible: parent.parent.hasSearch
                    Column {
                        width: parent.width
                        spacing: window.s(12)
                        Text {
                            text: "Recent Searches"
                            color: window.text
                            font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(16)
                        }
                        ListView {
                            width: parent.width; height: window.s(32)
                            orientation: ListView.Horizontal; spacing: window.s(8)
                            model: searchHistoryModel; clip: true; interactive: false
                            add: Transition {
                                ParallelAnimation {
                                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 400 }
                                    NumberAnimation { property: "x"; from: -window.s(20); duration: 400; easing.type: Easing.OutQuart }
                                }
                            }
                            remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 200 } }
                            displaced: Transition { NumberAnimation { property: "x"; duration: 300; easing.type: Easing.OutQuart } }
                            delegate: Rectangle {
                                width: queryText.width + window.s(35); height: window.s(32)
                                radius: window.s(8); color: window.surface0
                                border.color: histMouse.containsMouse ? window.surface2 : window.surface1
                                Text {
                                    id: queryText; text: model.query; color: window.text
                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(13)
                                    anchors.left: parent.left; anchors.leftMargin: window.s(10)
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                MouseArea {
                                    id: histMouse; anchors.fill: parent; hoverEnabled: true
                                    onClicked: { searchInput.text = model.query; doSearch(model.query) }
                                }
                                Rectangle {
                                    width: window.s(20); height: window.s(20); radius: window.s(10)
                                    color: closeMouse.containsMouse ? window.surface1 : "transparent"
                                    anchors.right: parent.right; anchors.rightMargin: window.s(5)
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text { text: "×"; anchors.centerIn: parent; color: window.subtext0; font.pixelSize: window.s(14) }
                                    MouseArea {
                                        id: closeMouse; anchors.fill: parent; hoverEnabled: true
                                        onClicked: { searchHistoryModel.remove(index); window.saveHistory() }
                                    }
                                }
                            }
                        }
                    }
                }
                Item {
                    width: parent.width
                    height: parent.parent.watchSectionH
                    visible: parent.parent.hasWatch
                    Column {
                        width: parent.width
                        spacing: window.s(12)
                        Text {
                            text: "Watch History"
                            color: window.text
                            font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(16)
                        }
                        ListView {
                            width: parent.width; height: window.s(200)
                            orientation: ListView.Horizontal; spacing: window.s(15)
                            model: watchHistoryModel; clip: true
                            delegate: PosterDelegate {}
                            ScrollBar.horizontal: ScrollBar {
                                active: true
                                contentItem: Rectangle { radius: window.s(2); color: window.surface2 }
                            }
                        }
                    }
                }
                Item {
                    width: parent.width
                    height: parent.parent.popularLabelH
                    Text {
                        anchors.top: parent.top; anchors.topMargin: window.s(4)
                        text: window.mediaType === "movie" ? "Popular Movies" : "Popular TV Shows"
                        color: window.text
                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(16)
                    }
                }
            }
        }
    }

    // --- UI LAYOUT ---
    Rectangle {
        id: mainBg
        width: parent.width; height: parent.height
        anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
        radius: window.s(14)
        color: Qt.rgba(window.base.r, window.base.g, window.base.b, 0.95)
        border.color: Qt.rgba(window.text.r, window.text.g, window.text.b, 0.08)
        border.width: 1
        clip: true
        transform: Translate { y: (1 - window.introPhase) * window.s(50) }
        opacity: window.introPhase
        ColumnLayout {
            anchors.fill: parent
            spacing: 0
            visible: window.currentView === "search"
            Rectangle {
                Layout.alignment: Qt.AlignTop; Layout.fillWidth: true; Layout.preferredHeight: window.s(120); color: "transparent"
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: window.s(15); spacing: window.s(10)
                    RowLayout {
                        Layout.fillWidth: true; spacing: window.s(15)
                        Rectangle {
                            Layout.preferredWidth: window.s(200); Layout.preferredHeight: window.s(36); radius: window.s(10); color: window.surface0
                            Rectangle {
                                id: tabHighlight
                                width: parent.width / 2 - window.s(4); height: parent.height - window.s(8)
                                y: window.s(4); radius: window.s(8); color: window.mediaType === "movie" ? window.mauve : window.blue; z: 0
                                property real targetX: window.mediaType === "movie" ? window.s(4) : (parent.width / 2)
                                property real actualX: targetX
                                Behavior on actualX { NumberAnimation { duration: 300; easing.type: Easing.OutQuart } }
                                x: actualX
                            }
                            RowLayout {
                                anchors.fill: parent; spacing: 0
                                MouseArea {
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    onClicked: { window.mediaType = "movie"; if (searchInput.text !== "") doSearch(searchInput.text) }
                                    Text { anchors.centerIn: parent; text: "Movies"; font.family: "JetBrains Mono"; font.weight: window.mediaType === "movie" ? Font.Bold : Font.Medium; font.pixelSize: window.s(13); color: window.mediaType === "movie" ? window.crust : window.text }
                                }
                                MouseArea {
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    onClicked: { window.mediaType = "tv"; if (searchInput.text !== "") doSearch(searchInput.text) }
                                    Text { anchors.centerIn: parent; text: "TV Shows"; font.family: "JetBrains Mono"; font.weight: window.mediaType === "tv" ? Font.Bold : Font.Medium; font.pixelSize: window.s(13); color: window.mediaType === "tv" ? window.crust : window.text }
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        CustomComboBox {
                            id: filterSelector
                            Layout.preferredWidth: window.s(180)
                            model: ["Default", "Year (Newest)", "Year (Oldest)", "Title (A-Z)", "Title (Z-A)", "Rating (Best)", "Rating (Worst)"]
                            onActivated: {
                                window.filterSort = currentText
                                applyFiltersAndPopulate()
                                applyFiltersToPopular()
                            }
                        }
                    }
                    TextField {
                        id: searchInput
                        Layout.fillWidth: true; Layout.preferredHeight: window.s(42)
                        background: Rectangle {
                            color: searchInput.activeFocus ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.6) : window.surface0
                            radius: window.s(10); border.color: searchInput.activeFocus ? window.surface2 : "transparent"
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        color: window.text; font.family: "JetBrains Mono"; font.pixelSize: window.s(15); leftPadding: window.s(15)
                        placeholderText: "Search"
                        placeholderTextColor: window.subtext0; verticalAlignment: TextInput.AlignVCenter
                        onTextChanged: {
                            if (text.trim() === "") { searchResults.clear(); window.isSearchingNetwork = false; searchDebounceTimer.stop() }
                            else searchDebounceTimer.restart()
                        }
                        Keys.onRightPressed: {
                            window.isKeyboardNav = true; keyboardNavTimer.restart()
                            let g = getActiveGrid()
                            if (g && g.count > 0 && g.currentIndex < g.count - 1) g.currentIndex++
                            event.accepted = true
                        }
                        Keys.onLeftPressed: {
                            window.isKeyboardNav = true; keyboardNavTimer.restart()
                            let g = getActiveGrid()
                            if (g && g.count > 0 && g.currentIndex > 0) g.currentIndex--
                            event.accepted = true
                        }
                        Keys.onDownPressed: {
                            window.isKeyboardNav = true; keyboardNavTimer.restart()
                            let g = getActiveGrid()
                            if (g && g.count > 0) {
                                let columns = Math.max(1, Math.floor(g.width / g.cellWidth))
                                if (g.currentIndex + columns < g.count) g.currentIndex += columns
                            }
                            event.accepted = true
                        }
                        Keys.onUpPressed: {
                            window.isKeyboardNav = true; keyboardNavTimer.restart()
                            let g = getActiveGrid()
                            if (g && g.count > 0) {
                                let columns = Math.max(1, Math.floor(g.width / g.cellWidth))
                                if (g.currentIndex - columns >= 0) g.currentIndex -= columns
                            }
                            event.accepted = true
                        }
                        Keys.onTabPressed: { window.mediaType = window.mediaType === "movie" ? "tv" : "movie"; if (text.trim() !== "") doSearch(text); event.accepted = true }
                        Keys.onBacktabPressed: { window.mediaType = window.mediaType === "movie" ? "tv" : "movie"; if (text.trim() !== "") doSearch(text); event.accepted = true }
                        Keys.onReturnPressed: {
                            if (text.trim() !== "" && searchResults.count === 0 && !window.isSearchingNetwork) {
                                doSearch(text)
                            } else if (window.isKeyboardNav) {
                                let g = getActiveGrid()
                                if (g && g.count > 0 && g.currentIndex >= 0 && g.currentIndex < g.count) {
                                    let item = g.model.get(g.currentIndex)
                                    if (item) {
                                        if (item.type === "movie") startSourceCheck("movie", item.imdbId, item.title, item.poster, 0, 0)
                                        else loadSeriesDetails(item.imdbId, item.title, item.poster)
                                    }
                                }
                            }
                            event.accepted = true
                        }
                    }
                }
            }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5) }
            Item {
                Layout.fillWidth: true; Layout.fillHeight: true
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(window.base.r, window.base.g, window.base.b, 0.8)
                    visible: window.isSearchingNetwork || (!window.isSearchMode && window.isLoadingPopular)
                    z: 10
                    ColumnLayout {
                        anchors.centerIn: parent; spacing: window.s(15)
                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            width: window.s(34); height: window.s(34)
                            property real spinAngle: 0
                            NumberAnimation on spinAngle {
                                from: 0; to: 360; duration: 900
                                loops: Animation.Infinite; running: true
                                easing.type: Easing.Linear
                            }
                            Canvas {
                                anchors.fill: parent
                                property real angle: parent.spinAngle
                                onAngleChanged: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.reset()
                                    var cx = width / 2, cy = height / 2, r = width / 2 - 3
                                    var startRad = (parent.spinAngle - 90) * Math.PI / 180
                                    var endRad = startRad + 1.7 * Math.PI
                                    ctx.beginPath()
                                    ctx.arc(cx, cy, r, startRad, endRad)
                                    ctx.strokeStyle = window.mauve
                                    ctx.lineWidth = 3
                                    ctx.lineCap = "round"
                                    ctx.stroke()
                                }
                            }
                        }
                        Text { Layout.alignment: Qt.AlignHCenter; text: "Loading..."; color: window.text; font.family: "JetBrains Mono"; font.pixelSize: window.s(14) }
                    }
                }
                Item {
                    anchors.fill: parent; anchors.margins: window.s(15); visible: !window.isSearchingNetwork
                    Component {
                        id: gridHighlightComp
                        Item {
                            z: 0
                            Rectangle {
                                color: window.surface0; border.color: window.surface1; border.width: 1; radius: window.s(10)
                                property real actX: parent.GridView.view.currentItem ? parent.GridView.view.currentItem.x + window.s(5) : 0
                                property real actY: parent.GridView.view.currentItem ? parent.GridView.view.currentItem.y + window.s(5) : 0
                                x: actX; y: actY; width: parent.GridView.view.cellWidth - window.s(10); height: parent.GridView.view.cellHeight - window.s(10)
                                Behavior on actX { enabled: window.isKeyboardNav; NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                                Behavior on actY { enabled: window.isKeyboardNav; NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                                opacity: parent.GridView.view.count > 0 && parent.GridView.view.currentIndex >= 0 ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 300 } }
                            }
                        }
                    }
                    Component {
                        id: mediaGridDelegate
                        Item {
                            width: GridView.view.cellWidth; height: GridView.view.cellHeight; z: 1
                            Rectangle {
                                anchors.fill: parent; anchors.margins: window.s(5); radius: window.s(10); color: "transparent"
                                property bool isActive: index === parent.parent.GridView.view.currentIndex
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: window.s(10); spacing: window.s(8)
                                    Rectangle {
                                        Layout.fillWidth: true; Layout.fillHeight: true; radius: window.s(8); color: window.crust; clip: true
                                        scale: parent.parent.isActive && window.isKeyboardNav ? 1.03 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                                        Image {
                                            id: gridImage
                                            anchors.fill: parent
                                            source: model.poster !== "" ? model.poster : ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true; smooth: true; cache: true
                                            visible: status === Image.Ready
                                        }
                                        Rectangle {
                                            anchors.fill: parent; color: window.surface0
                                            visible: model.poster === "" || gridImage.status === Image.Error || gridImage.status === Image.Loading
                                            radius: window.s(8)
                                            property bool isLoading: model.poster !== "" && gridImage.status === Image.Loading
                                            Rectangle {
                                                anchors.fill: parent; radius: window.s(8); color: "transparent"
                                                visible: parent.isLoading
                                                Rectangle {
                                                    width: parent.width * 0.4; height: parent.height
                                                    color: Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.4)
                                                    property real shimX: -parent.parent.width
                                                    x: shimX
                                                    NumberAnimation on shimX {
                                                        from: -parent.parent.width
                                                        to: parent.parent.width * 1.5
                                                        duration: 1200; loops: Animation.Infinite
                                                        running: parent.parent.parent.isLoading
                                                        easing.type: Easing.InOutSine
                                                    }
                                                }
                                            }
                                            Text { anchors.centerIn: parent; width: parent.width - window.s(10); text: model.title || "Unknown"; color: window.subtext0; font.family: "JetBrains Mono"; font.pixelSize: window.s(12); wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter; visible: !parent.isLoading }
                                        }
                                        Rectangle {
                                            anchors.fill: parent; radius: window.s(8)
                                            color: window.mediaType === "tv" ? window.blue : window.mauve
                                            opacity: parent.parent.parent.isActive ? 0.2 : 0
                                            Behavior on opacity { NumberAnimation { duration: 200 } }
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true; text: model.title; font.family: "JetBrains Mono"; font.pixelSize: window.s(12); font.weight: Font.Bold
                                        color: parent.parent.isActive ? window.text : window.subtext0
                                        wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; lineHeight: 1.1; horizontalAlignment: Text.AlignHCenter
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }
                                    Text { Layout.fillWidth: true; text: model.year !== "N/A" ? model.year : ""; font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: window.surface2; horizontalAlignment: Text.AlignHCenter; visible: text !== "" }
                                }
                                MouseArea {
                                    anchors.fill: parent; hoverEnabled: true
                                    onEntered: { window.isKeyboardNav = false; parent.parent.GridView.view.currentIndex = index }
                                    onClicked: {
                                        if (model.type === "movie") startSourceCheck("movie", model.imdbId, model.title, model.poster, 0, 0)
                                        else loadSeriesDetails(model.imdbId, model.title, model.poster)
                                    }
                                }
                            }
                        }
                    }
                    GridView {
                        id: searchGrid
                        anchors.fill: parent; visible: window.isSearchMode
                        model: searchResults; cellWidth: Math.floor(width / 5); cellHeight: cellWidth * 1.5 + window.s(60)
                        boundsBehavior: Flickable.StopAtBounds; highlightFollowsCurrentItem: false; clip: true
                        ScrollBar.vertical: ScrollBar { active: true; contentItem: Rectangle { radius: window.s(2); color: window.surface2 } }
                        Behavior on contentY { NumberAnimation { duration: 300; easing.type: Easing.OutQuart } }
                        add: Transition { ParallelAnimation { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 400; easing.type: Easing.OutQuart } NumberAnimation { property: "y"; from: y + window.s(30); duration: 500; easing.type: Easing.OutQuart } NumberAnimation { property: "scale"; from: 0.9; to: 1; duration: 500; easing.type: Easing.OutBack } } }
                        highlight: gridHighlightComp; delegate: mediaGridDelegate
                    }
                    GridView {
                        id: movieGrid
                        anchors.fill: parent; visible: !window.isSearchMode && window.mediaType === "movie"
                        model: cachedTrendingMovies; cellWidth: Math.floor(width / 10); cellHeight: cellWidth * 1.5 + window.s(60)
                        header: dashboardHeaderComp; boundsBehavior: Flickable.StopAtBounds; highlightFollowsCurrentItem: false; clip: true
                        ScrollBar.vertical: ScrollBar { active: true; contentItem: Rectangle { radius: window.s(2); color: window.surface2 } }
                        Behavior on contentY { NumberAnimation { duration: 300; easing.type: Easing.OutQuart } }
                        highlight: gridHighlightComp; delegate: mediaGridDelegate
                    }
                    GridView {
                        id: tvGrid
                        anchors.fill: parent; visible: !window.isSearchMode && window.mediaType === "tv"
                        model: cachedTrendingTv; cellWidth: Math.floor(width / 10); cellHeight: cellWidth * 1.5 + window.s(60)
                        header: dashboardHeaderComp; boundsBehavior: Flickable.StopAtBounds; highlightFollowsCurrentItem: false; clip: true
                        ScrollBar.vertical: ScrollBar { active: true; contentItem: Rectangle { radius: window.s(2); color: window.surface2 } }
                        Behavior on contentY { NumberAnimation { duration: 300; easing.type: Easing.OutQuart } }
                        highlight: gridHighlightComp; delegate: mediaGridDelegate
                    }
                }
            }
        }
        // ==========================================
        // SERIES VIEW
        // ==========================================
        RowLayout {
            anchors.fill: parent; anchors.margins: window.s(20); spacing: window.s(25)
            visible: window.currentView === "series"
            ColumnLayout {
                Layout.preferredWidth: window.s(220); Layout.minimumWidth: window.s(220); Layout.maximumWidth: window.s(220)
                Layout.fillHeight: true; spacing: window.s(12)
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: window.s(300); radius: window.s(14); color: window.crust; clip: true
                    Image {
                        anchors.fill: parent
                        source: window.selectedPoster !== "" ? window.selectedPoster : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true; smooth: true; cache: true
                        sourceSize.width: window.s(440); sourceSize.height: window.s(600)
                        visible: status === Image.Ready
                    }
                    Rectangle {
                        anchors.fill: parent; color: window.surface0; radius: window.s(14)
                        visible: window.selectedPoster === "" || parent.children[0].status === Image.Error || parent.children[0].status === Image.Loading
                        Text { anchors.centerIn: parent; width: parent.width - window.s(10); text: window.selectedTitle; color: window.subtext0; font.family: "JetBrains Mono"; font.pixelSize: window.s(14); wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
                    }
                }
                Text {
                    Layout.fillWidth: true; text: window.selectedTitle
                    font.family: "JetBrains Mono"; font.pixelSize: window.s(16); font.weight: Font.Bold
                    color: window.text; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                    maximumLineCount: 3; elide: Text.ElideRight
                }
                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(window.s(120), descText.implicitHeight + window.s(8))
                    Layout.maximumHeight: window.s(120)
                    visible: window.selectedDescription !== ""
                    clip: true; contentHeight: descText.implicitHeight
                    ScrollBar.vertical: ScrollBar { contentItem: Rectangle { radius: window.s(2); color: window.surface2; implicitWidth: window.s(3) } }
                    Text {
                        id: descText
                        width: parent.width - window.s(8)
                        text: window.selectedDescription
                        font.family: "JetBrains Mono"; font.pixelSize: window.s(11)
                        color: window.subtext0; wrapMode: Text.WordWrap; lineHeight: 1.4
                        Behavior on opacity { NumberAnimation { duration: 400 } }
                        opacity: window.selectedDescription !== "" ? 1 : 0
                    }
                }
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: window.s(45); radius: window.s(10)
                    property bool isHovered: backMouse.containsMouse
                    color: isHovered ? window.surface2 : window.surface1
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Text { anchors.centerIn: parent; text: "← Back"; font.family: "JetBrains Mono"; font.pixelSize: window.s(14); font.weight: Font.Medium; color: window.text }
                    MouseArea { id: backMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { window.currentView = "search"; searchInput.forceActiveFocus(); saveUiState() } }
                }
                Item { Layout.fillHeight: true }
            }
            ColumnLayout {
                Layout.fillWidth: true; Layout.fillHeight: true; spacing: window.s(12)
                Item {
                    Layout.fillWidth: true; Layout.preferredHeight: window.s(44)
                    ListView {
                        id: seasonList
                        anchors.fill: parent
                        orientation: ListView.Horizontal; model: seasonModel; spacing: window.s(8); clip: true
                        Behavior on contentX { NumberAnimation { duration: 350; easing.type: Easing.OutQuart } }
                        delegate: Rectangle {
                            width: seasonLabelText.width + window.s(28); height: window.s(38); radius: window.s(10)
                            property bool isActive: window.currentSeason === model.seasonNum
                            color: isActive ? (window.mediaType === "tv" ? window.blue : window.mauve) : window.surface0
                            border.color: isActive ? color : window.surface1; border.width: 1
                            Behavior on color { ColorAnimation { duration: 280; easing.type: Easing.OutQuart } }
                            Behavior on border.color { ColorAnimation { duration: 280; easing.type: Easing.OutQuart } }
                            scale: isActive ? 1.04 : 1.0
                            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                            Text {
                                id: seasonLabelText
                                anchors.centerIn: parent
                                text: "S" + model.seasonNum
                                font.family: "JetBrains Mono"; font.pixelSize: window.s(13); font.weight: isActive ? Font.Bold : Font.Medium
                                color: isActive ? window.crust : window.text
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (window.currentSeason !== model.seasonNum) {
                                        window.currentSeason = model.seasonNum
                                        updateEpisodes(model.seasonNum)
                                        saveUiState()
                                    }
                                }
                            }
                        }
                    }
                }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5) }
                Item {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    ListView {
                        id: epList
                        anchors.fill: parent
                        model: episodeModel; spacing: window.s(6); clip: true
                        opacity: window.seasonSwitching ? 0 : 1
                        Behavior on opacity {
                            NumberAnimation {
                                duration: window.seasonSwitching ? 180 : 250
                                easing.type: window.seasonSwitching ? Easing.InQuad : Easing.OutQuad
                            }
                        }
                        transform: Translate {
                            y: window.seasonSwitching ? window.s(8) : 0
                            Behavior on y {
                                NumberAnimation {
                                    duration: window.seasonSwitching ? 180 : 280
                                    easing.type: window.seasonSwitching ? Easing.InQuad : Easing.OutQuart
                                }
                            }
                        }
                        ScrollBar.vertical: ScrollBar { active: true; contentItem: Rectangle { radius: window.s(2); color: window.surface2; implicitWidth: window.s(4) } }
                        Text {
                            anchors.centerIn: parent
                            visible: window.isLoadingSeries
                            text: "Fetching episodes..."
                            color: window.subtext0; font.family: "JetBrains Mono"; font.pixelSize: window.s(13)
                        }
                        highlight: Rectangle {
                            color: window.surface0; border.color: window.surface2; border.width: 1; radius: window.s(10); z: 0
                            Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutQuart } }
                        }
                        highlightFollowsCurrentItem: true
                        highlightMoveVelocity: -1
                        delegate: Item {
                            width: ListView.view.width; height: window.s(58); z: 1
                            property bool isCurrent: ListView.isCurrentItem
                            Rectangle {
                                anchors.fill: parent; radius: window.s(10)
                                color: epMouse.containsMouse || isCurrent ? window.surface0 : "transparent"
                                border.color: epMouse.containsMouse || isCurrent ? window.surface2 : "transparent"; border.width: 1
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: window.s(10); spacing: window.s(12)
                                    Rectangle {
                                        Layout.preferredWidth: window.s(36); Layout.preferredHeight: window.s(36)
                                        radius: window.s(8)
                                        color: isCurrent || epMouse.containsMouse ? window.blue : window.surface1
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: model.epNum
                                            font.family: "JetBrains Mono"; font.pixelSize: window.s(13); font.weight: Font.Bold
                                            color: isCurrent || epMouse.containsMouse ? window.crust : window.subtext0
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                        }
                                    }
                                    Column {
                                        Layout.fillWidth: true; spacing: window.s(2)
                                        Text {
                                            width: parent.width
                                            text: model.epTitle
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: model.hasRealTitle ? window.s(13) : window.s(12)
                                            font.weight: model.hasRealTitle ? Font.Medium : Font.Normal
                                            color: model.hasRealTitle ? window.text : window.subtext0
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                                MouseArea {
                                    id: epMouse; anchors.fill: parent; hoverEnabled: true
                                    onClicked: {
                                        epList.currentIndex = index
                                        startSourceCheck("tv", window.selectedImdbId, window.selectedTitle, window.selectedPoster, window.currentSeason, model.epNum)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    // ==========================================
    // SOURCE CHECKER MODAL OVERLAY
    // ==========================================
    Rectangle {
        id: sourceModalOverlay
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.7)
        opacity: window.isSourceModalOpen ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
        z: 100
        MouseArea {
            anchors.fill: parent
            onClicked: window.closeSourceModal()
        }
        Rectangle {
            width: window.s(480); height: window.s(600)
            anchors.centerIn: parent
            radius: window.s(14)
            color: window.base
            border.color: window.surface2
            border.width: 1
            clip: true
            scale: window.isSourceModalOpen ? 1.0 : 0.92
            Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack } }
            MouseArea { anchors.fill: parent }
            ColumnLayout {
                anchors.fill: parent; spacing: 0
                // Header
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: window.s(75); color: window.surface0
                    Rectangle { width: parent.width; height: 1; color: window.surface1; anchors.bottom: parent.bottom }
                    RowLayout {
                        anchors.fill: parent; anchors.margins: window.s(16)
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: window.s(4)
                            Text {
                                text: window.checkingState === "checking" ? "Finding Stream..."
                                    : window.checkingState === "found"    ? "Stream Ready!"
                                    :                                       "No Streams Found"
                                color: window.checkingState === "found"      ? window.green
                                     : window.checkingState === "failed_all" ? window.red
                                     :                                         window.text
                                font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(17)
                                Behavior on color { ColorAnimation { duration: 300 } }
                            }
                            Text {
                                text: window.pendingMedia.title || "Loading..."
                                color: window.subtext0; font.family: "JetBrains Mono"; font.pixelSize: window.s(12)
                                elide: Text.ElideRight; Layout.fillWidth: true
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: window.s(32); Layout.preferredHeight: window.s(32); radius: window.s(8)
                            color: modalCloseMouse.containsMouse ? window.surface2 : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text { anchors.centerIn: parent; text: "×"; color: window.subtext0; font.pixelSize: window.s(20) }
                            MouseArea { id: modalCloseMouse; anchors.fill: parent; hoverEnabled: true; onClicked: window.closeSourceModal() }
                        }
                    }
                }
                // Body
                Item {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    ListView {
                        id: sourceListUI
                        anchors.fill: parent; anchors.margins: window.s(14)
                        model: sourceModel; spacing: window.s(8); clip: true
                        visible: window.checkingState !== "failed_all"
                        delegate: Rectangle {
                            width: ListView.view.width; height: window.s(52); radius: window.s(10)
                            color: {
                                if (model.status === "checking") return Qt.rgba(window.blue.r,  window.blue.g,  window.blue.b,  0.12)
                                if (model.status === "success")  return Qt.rgba(window.green.r, window.green.g, window.green.b, 0.12)
                                if (model.status === "failed")   return Qt.rgba(window.red.r,   window.red.g,   window.red.b,   0.07)
                                return window.surface0
                            }
                            border.color: {
                                if (model.status === "checking") return window.blue
                                if (model.status === "success")  return window.green
                                if (model.status === "failed")   return Qt.rgba(window.red.r, window.red.g, window.red.b, 0.3)
                                return window.surface1
                            }
                            border.width: (model.status === "checking" || model.status === "success") ? 2 : 1
                            Behavior on color { ColorAnimation { duration: 250 } }
                            Behavior on border.color { ColorAnimation { duration: 250 } }
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: window.s(14); anchors.rightMargin: window.s(10)
                                anchors.topMargin: 0; anchors.bottomMargin: 0
                                spacing: window.s(10)
                                Text {
                                    text: "★"
                                    font.pixelSize: window.s(13)
                                    color: window.mauve
                                    opacity: (window.sourcePrefs[window.pendingMedia.imdbId || ""] || "") === model.name ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                    Layout.preferredWidth: window.s(16)
                                }
                                Text {
                                    text: model.name
                                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(14)
                                    color: model.status === "checking" ? window.blue
                                         : model.status === "success"  ? window.green
                                         : model.status === "failed"   ? Qt.rgba(window.red.r, window.red.g, window.red.b, 0.7)
                                         :                               window.text
                                    Layout.fillWidth: true
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                                Item {
                                    Layout.preferredWidth: window.s(22); Layout.preferredHeight: window.s(22)
                                    Rectangle {
                                        anchors.fill: parent; radius: width / 2
                                        color: "transparent"; border.color: window.surface2; border.width: 2
                                        visible: model.status === "pending"
                                    }
                                    Item {
                                        anchors.fill: parent
                                        visible: model.status === "checking"
                                        property real spinAngle: 0
                                        NumberAnimation on spinAngle {
                                            from: 0; to: 360; duration: 700
                                            loops: Animation.Infinite
                                            running: model.status === "checking"
                                            easing.type: Easing.Linear
                                        }
                                        Canvas {
                                            anchors.fill: parent
                                            property real angle: parent.spinAngle
                                            onAngleChanged: requestPaint()
                                            onPaint: {
                                                var ctx = getContext("2d")
                                                ctx.reset()
                                                var cx = width / 2, cy = height / 2, r = width / 2 - 2
                                                var startRad = (parent.spinAngle - 90) * Math.PI / 180
                                                var endRad   = startRad + 1.6 * Math.PI
                                                ctx.beginPath()
                                                ctx.arc(cx, cy, r, startRad, endRad)
                                                ctx.strokeStyle = window.blue
                                                ctx.lineWidth = 2.5
                                                ctx.lineCap = "round"
                                                ctx.stroke()
                                            }
                                        }
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: "✗"; color: Qt.rgba(window.red.r, window.red.g, window.red.b, 0.7)
                                        font.weight: Font.Bold; font.pixelSize: window.s(14)
                                        visible: model.status === "failed"
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: "✓"; color: window.green
                                        font.weight: Font.Bold; font.pixelSize: window.s(14)
                                        visible: model.status === "success"
                                    }
                                }
                            }
                        }
                    }
                    ColumnLayout {
                        anchors.centerIn: parent; width: parent.width - window.s(40); spacing: window.s(20)
                        visible: window.checkingState === "failed_all"
                        Text {
                            Layout.fillWidth: true
                            text: "All stream sources failed for this title."
                            color: window.subtext0; font.family: "JetBrains Mono"; font.pixelSize: window.s(13)
                            wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter; lineHeight: 1.3
                        }
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: window.s(45); radius: window.s(10)
                            color: fmhyMouse.containsMouse ? window.blue : window.surface1
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text { anchors.centerIn: parent; text: "Browse Alternative Sites"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(13); color: fmhyMouse.containsMouse ? window.crust : window.text }
                            MouseArea {
                                id: fmhyMouse; anchors.fill: parent; hoverEnabled: true
                                onClicked: { Quickshell.execDetached(["xdg-open", "https://fmhy.net/video#streaming-sites"]); window.closeSourceModal() }
                            }
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: window.checkingState === "found" ? window.s(80) : 0
                    color: window.surface0; clip: true
                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 280; easing.type: Easing.OutQuart } }
                    Rectangle { width: parent.width; height: 1; color: window.surface1; anchors.top: parent.top }
                    RowLayout {
                        anchors.fill: parent; anchors.margins: window.s(14); spacing: window.s(10)
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: window.s(48); radius: window.s(10)
                            property bool isPreferred: (window.sourcePrefs[window.pendingMedia.imdbId || ""] || "") === window.foundSourceName
                            color: markWorksMouse.containsMouse
                                ? Qt.rgba(window.green.r, window.green.g, window.green.b, 0.25)
                                : Qt.rgba(window.green.r, window.green.g, window.green.b, isPreferred ? 0.20 : 0.10)
                            border.color: isPreferred ? window.green : Qt.rgba(window.green.r, window.green.g, window.green.b, 0.4)
                            border.width: isPreferred ? 2 : 1
                            Behavior on color { ColorAnimation { duration: 150 } }
                            ColumnLayout {
                                anchors.centerIn: parent; spacing: window.s(2)
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: parent.parent.isPreferred ? "★ Preferred Source" : "Mark as Working"
                                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(12)
                                    color: window.green
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: window.foundSourceName !== "" ? window.foundSourceName : ""
                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(10)
                                    color: Qt.rgba(window.green.r, window.green.g, window.green.b, 0.7)
                                    visible: text !== ""
                                }
                            }
                            MouseArea {
                                id: markWorksMouse; anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    if (window.pendingMedia.imdbId && window.foundSourceName !== "") {
                                        saveSourcePref(window.pendingMedia.imdbId, window.foundSourceName)
                                    }
                                }
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: window.s(110); Layout.preferredHeight: window.s(48); radius: window.s(10)
                            color: tryNextMouse2.containsMouse ? window.surface2 : window.surface1
                            border.color: window.surface2; border.width: 1
                            Behavior on color { ColorAnimation { duration: 150 } }
                            ColumnLayout {
                                anchors.centerIn: parent; spacing: window.s(2)
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Try Next"
                                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(12)
                                    color: window.text
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Not working?"
                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(10)
                                    color: window.subtext0
                                }
                            }
                            MouseArea { id: tryNextMouse2; anchors.fill: parent; hoverEnabled: true; onClicked: window.skipToNextSource() }
                        }
                    }
                }
            }
        }
    }
}
