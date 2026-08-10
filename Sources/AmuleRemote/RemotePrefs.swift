// Remote amuled preferences, transported via EC_OP_GET/SET_PREFERENCES.
import Foundation

struct RemotePrefs {
    // General
    var nick = ""

    // Connections
    var dlCap: UInt64 = 0          // line capacity, kB/s
    var ulCap: UInt64 = 0
    var maxDL: UInt64 = 0          // limits, kB/s (0 = unlimited)
    var maxUL: UInt64 = 0
    var slotAllocation: UInt64 = 0
    var tcpPort: UInt64 = 4662
    var udpPort: UInt64 = 4672
    var udpDisabled = false
    var maxFileSources: UInt64 = 0
    var maxConnections: UInt64 = 0
    var autoconnect = false
    var reconnect = false
    var networkED2K = true
    var networkKad = true

    // Servers
    var removeDeadServers = false
    var deadServerRetries: UInt64 = 0
    var serversAutoUpdate = false
    var serversAddFromServer = false
    var serversAddFromClient = false
    var useScoreSystem = false
    var smartIDCheck = false
    var safeServerConnect = false
    var autoconnStaticOnly = false
    var manualHighPrio = false
    var serversUpdateURL = ""

    // Files
    var ichEnabled = false
    var aichTrust = false
    var newPaused = false
    var newAutoDLPrio = false
    var previewPrio = false
    var newAutoULPrio = false
    var ulFullChunks = false
    var startNextPaused = false
    var resumeSameCat = false
    var saveSources = false
    var extractMetadata = false
    var allocFullSize = false
    var checkFreeSpace = false
    var minFreeSpace: UInt64 = 0

    // Directories (remotely editable via SetIncomingDir/SetTempDir)
    var dirIncoming = ""
    var dirTemp = ""
    var sharedDirs: [String] = []
    var shareHidden = false
    var autoRescanShared = false
    // Only send the directories section back if we actually received it,
    // otherwise an empty sharedDirs would wipe the daemon's list.
    var directoriesLoaded = false

    // Message filter
    var msgFilterEnabled = false
    var msgFilterAll = false
    var msgFilterFriends = false
    var msgFilterSecure = false
    var msgFilterByKeyword = false
    var msgFilterKeywords = ""

    // Online signature
    var onlineSigEnabled = false

    // Security
    var canSeeShares: UInt64 = 0
    var ipfilterClients = false
    var ipfilterServers = false
    var ipfilterAutoUpdate = false
    var ipfilterUpdateURL = ""
    var ipfilterLevel: UInt64 = 127
    var ipfilterFilterLAN = false
    var useSecIdent = false
    var obfuscationSupported = false
    var obfuscationRequested = false
    var obfuscationRequired = false

    // Core tweaks
    var maxConnPerFive: UInt64 = 0
    var fileBufferSize: UInt64 = 0
    var uploadQueueSize: UInt64 = 0
    var serverKeepAliveTimeout: UInt64 = 0

    // Remote controls (webserver)
    var webserverAutorun = false
    var webserverPort: UInt64 = 4711
    var webserverGuest = false
    var webserverUseGzip = false
    var webserverRefresh: UInt64 = 0

    // Kademlia
    var kadUpdateURL = ""

    var categories: [CategoryItem] = []

    // MARK: parse

    static func parse(_ p: ECPacket) -> RemotePrefs {
        var r = RemotePrefs()

        if let g = p.tag(.prefsGeneral) {
            r.nick = g.childString(.userNick) ?? ""
        }
        if let c = p.tag(.prefsConnections) {
            r.dlCap = c.childNumber(.connDLCap) ?? 0
            r.ulCap = c.childNumber(.connULCap) ?? 0
            r.maxDL = c.childNumber(.connMaxDL) ?? 0
            r.maxUL = c.childNumber(.connMaxUL) ?? 0
            r.slotAllocation = c.childNumber(.connSlotAllocation) ?? 0
            r.tcpPort = c.childNumber(.connTCPPort) ?? 4662
            r.udpPort = c.childNumber(.connUDPPort) ?? 4672
            r.udpDisabled = c.child(.connUDPDisable) != nil && (c.childNumber(.connUDPDisable) ?? 1) != 0
            r.maxFileSources = c.childNumber(.connMaxFileSources) ?? 0
            r.maxConnections = c.childNumber(.connMaxConn) ?? 0
            r.autoconnect = (c.childNumber(.connAutoconnect) ?? 0) != 0
            r.reconnect = (c.childNumber(.connReconnect) ?? 0) != 0
            r.networkED2K = (c.childNumber(.networkED2K) ?? 1) != 0
            r.networkKad = (c.childNumber(.networkKademlia) ?? 1) != 0
        }
        if let s = p.tag(.prefsServers) {
            r.removeDeadServers = (s.childNumber(.serversRemoveDead) ?? 0) != 0
            r.deadServerRetries = s.childNumber(.serversDeadServerRetries) ?? 0
            r.serversAutoUpdate = (s.childNumber(.serversAutoUpdate) ?? 0) != 0
            r.serversAddFromServer = (s.childNumber(.serversAddFromServer) ?? 0) != 0
            r.serversAddFromClient = (s.childNumber(.serversAddFromClient) ?? 0) != 0
            r.useScoreSystem = (s.childNumber(.serversUseScoreSystem) ?? 0) != 0
            r.smartIDCheck = (s.childNumber(.serversSmartIDCheck) ?? 0) != 0
            r.safeServerConnect = (s.childNumber(.serversSafeServerConnect) ?? 0) != 0
            r.autoconnStaticOnly = (s.childNumber(.serversAutoconnStaticOnly) ?? 0) != 0
            r.manualHighPrio = (s.childNumber(.serversManualHighPrio) ?? 0) != 0
            r.serversUpdateURL = s.childString(.serversUpdateURL) ?? ""
        }
        if let f = p.tag(.prefsFiles) {
            r.ichEnabled = (f.childNumber(.filesICHEnabled) ?? 0) != 0
            r.aichTrust = (f.childNumber(.filesAICHTrust) ?? 0) != 0
            r.newPaused = (f.childNumber(.filesNewPaused) ?? 0) != 0
            r.newAutoDLPrio = (f.childNumber(.filesNewAutoDLPrio) ?? 0) != 0
            r.previewPrio = (f.childNumber(.filesPreviewPrio) ?? 0) != 0
            r.newAutoULPrio = (f.childNumber(.filesNewAutoULPrio) ?? 0) != 0
            r.ulFullChunks = (f.childNumber(.filesULFullChunks) ?? 0) != 0
            r.startNextPaused = (f.childNumber(.filesStartNextPaused) ?? 0) != 0
            r.resumeSameCat = (f.childNumber(.filesResumeSameCat) ?? 0) != 0
            r.saveSources = (f.childNumber(.filesSaveSources) ?? 0) != 0
            r.extractMetadata = (f.childNumber(.filesExtractMetadata) ?? 0) != 0
            r.allocFullSize = (f.childNumber(.filesAllocFullSize) ?? 0) != 0
            r.checkFreeSpace = (f.childNumber(.filesCheckFreeSpace) ?? 0) != 0
            r.minFreeSpace = f.childNumber(.filesMinFreeSpace) ?? 0
        }
        if let d = p.tag(.prefsDirectories) {
            r.dirIncoming = d.childString(.directoriesIncoming) ?? ""
            r.dirTemp = d.childString(.directoriesTemp) ?? ""
            if let shared = d.child(.directoriesShared) {
                r.sharedDirs = shared.children.compactMap(\.stringValue)
            }
            r.shareHidden = (d.childNumber(.directoriesShareHidden) ?? 0) != 0
            r.autoRescanShared = (d.childNumber(.directoriesAutoRescan) ?? 0) != 0
            r.directoriesLoaded = true
        }
        if let m = p.tag(.prefsMessageFilter) {
            r.msgFilterEnabled = (m.childNumber(.msgFilterEnabled) ?? 0) != 0
            r.msgFilterAll = (m.childNumber(.msgFilterAll) ?? 0) != 0
            r.msgFilterFriends = (m.childNumber(.msgFilterFriends) ?? 0) != 0
            r.msgFilterSecure = (m.childNumber(.msgFilterSecure) ?? 0) != 0
            r.msgFilterByKeyword = (m.childNumber(.msgFilterByKeyword) ?? 0) != 0
            r.msgFilterKeywords = m.childString(.msgFilterKeywords) ?? ""
        }
        if let o = p.tag(.prefsOnlineSig) {
            r.onlineSigEnabled = (o.childNumber(.onlineSigEnabled) ?? 0) != 0
        }
        if let s = p.tag(.prefsSecurity) {
            r.canSeeShares = s.childNumber(.securityCanSeeShares) ?? 0
            r.ipfilterClients = (s.childNumber(.ipfilterClients) ?? 0) != 0
            r.ipfilterServers = (s.childNumber(.ipfilterServers) ?? 0) != 0
            r.ipfilterAutoUpdate = (s.childNumber(.ipfilterAutoUpdate) ?? 0) != 0
            r.ipfilterUpdateURL = s.childString(.ipfilterUpdateURL) ?? ""
            r.ipfilterLevel = s.childNumber(.ipfilterLevel) ?? 127
            r.ipfilterFilterLAN = (s.childNumber(.ipfilterFilterLAN) ?? 0) != 0
            r.useSecIdent = (s.childNumber(.securityUseSecIdent) ?? 0) != 0
            r.obfuscationSupported = (s.childNumber(.securityObfuscationSupported) ?? 0) != 0
            r.obfuscationRequested = (s.childNumber(.securityObfuscationRequested) ?? 0) != 0
            r.obfuscationRequired = (s.childNumber(.securityObfuscationRequired) ?? 0) != 0
        }
        if let t = p.tag(.prefsCoreTweaks) {
            r.maxConnPerFive = t.childNumber(.coretwMaxConnPerFive) ?? 0
            r.fileBufferSize = t.childNumber(.coretwFileBuffer) ?? 0
            r.uploadQueueSize = t.childNumber(.coretwULQueue) ?? 0
            r.serverKeepAliveTimeout = t.childNumber(.coretwSrvKeepaliveTimeout) ?? 0
        }
        if let w = p.tag(.prefsRemoteCtrl) {
            r.webserverAutorun = (w.childNumber(.webserverAutorun) ?? 0) != 0
            r.webserverPort = w.childNumber(.webserverPort) ?? 4711
            r.webserverGuest = (w.childNumber(.webserverGuest) ?? 0) != 0
            r.webserverUseGzip = (w.childNumber(.webserverUseGzip) ?? 0) != 0
            r.webserverRefresh = w.childNumber(.webserverRefresh) ?? 0
        }
        if let k = p.tag(.prefsKademlia) {
            r.kadUpdateURL = k.childString(.kademliaUpdateURL) ?? ""
        }
        if let cats = p.tag(.prefsCategories) {
            for c in cats.children where c.name == ECTagName.category.rawValue {
                r.categories.append(CategoryItem(
                    index: c.numberValue ?? 0,
                    title: c.childString(.categoryTitle) ?? "",
                    path: c.childString(.categoryPath) ?? "",
                    comment: c.childString(.categoryComment) ?? "",
                    color: c.childNumber(.categoryColor) ?? 0,
                    priority: c.childNumber(.categoryPrio) ?? 0
                ))
            }
        }
        return r
    }

    // MARK: build SET packet

    func buildSetPacket() -> ECPacket {
        var tags: [ECTag] = []

        var general = ECTag.empty(.prefsGeneral)
        general.children = [.string(.userNick, nick)]
        tags.append(general)

        var conn = ECTag.empty(.prefsConnections)
        conn.children = [
            .number(.connDLCap, dlCap),
            .number(.connULCap, ulCap),
            .number(.connMaxDL, maxDL),
            .number(.connMaxUL, maxUL),
            .number(.connSlotAllocation, slotAllocation),
            .number(.connTCPPort, tcpPort),
            .number(.connUDPPort, udpPort),
            .uint8(.connUDPDisable, udpDisabled ? 1 : 0),
            .number(.connMaxFileSources, maxFileSources),
            .number(.connMaxConn, maxConnections),
            .uint8(.connAutoconnect, autoconnect ? 1 : 0),
            .uint8(.connReconnect, reconnect ? 1 : 0),
            .uint8(.networkED2K, networkED2K ? 1 : 0),
            .uint8(.networkKademlia, networkKad ? 1 : 0),
        ]
        tags.append(conn)

        var srv = ECTag.empty(.prefsServers)
        srv.children = [
            .uint8(.serversRemoveDead, removeDeadServers ? 1 : 0),
            .number(.serversDeadServerRetries, deadServerRetries),
            .uint8(.serversAutoUpdate, serversAutoUpdate ? 1 : 0),
            .uint8(.serversAddFromServer, serversAddFromServer ? 1 : 0),
            .uint8(.serversAddFromClient, serversAddFromClient ? 1 : 0),
            .uint8(.serversUseScoreSystem, useScoreSystem ? 1 : 0),
            .uint8(.serversSmartIDCheck, smartIDCheck ? 1 : 0),
            .uint8(.serversSafeServerConnect, safeServerConnect ? 1 : 0),
            .uint8(.serversAutoconnStaticOnly, autoconnStaticOnly ? 1 : 0),
            .uint8(.serversManualHighPrio, manualHighPrio ? 1 : 0),
            .string(.serversUpdateURL, serversUpdateURL),
        ]
        tags.append(srv)

        var files = ECTag.empty(.prefsFiles)
        files.children = [
            .uint8(.filesICHEnabled, ichEnabled ? 1 : 0),
            .uint8(.filesAICHTrust, aichTrust ? 1 : 0),
            .uint8(.filesNewPaused, newPaused ? 1 : 0),
            .uint8(.filesNewAutoDLPrio, newAutoDLPrio ? 1 : 0),
            .uint8(.filesPreviewPrio, previewPrio ? 1 : 0),
            .uint8(.filesNewAutoULPrio, newAutoULPrio ? 1 : 0),
            .uint8(.filesULFullChunks, ulFullChunks ? 1 : 0),
            .uint8(.filesStartNextPaused, startNextPaused ? 1 : 0),
            .uint8(.filesResumeSameCat, resumeSameCat ? 1 : 0),
            .uint8(.filesSaveSources, saveSources ? 1 : 0),
            .uint8(.filesExtractMetadata, extractMetadata ? 1 : 0),
            .uint8(.filesAllocFullSize, allocFullSize ? 1 : 0),
            .uint8(.filesCheckFreeSpace, checkFreeSpace ? 1 : 0),
            .number(.filesMinFreeSpace, minFreeSpace),
        ]
        tags.append(files)

        var msg = ECTag.empty(.prefsMessageFilter)
        msg.children = [
            .uint8(.msgFilterEnabled, msgFilterEnabled ? 1 : 0),
            .uint8(.msgFilterAll, msgFilterAll ? 1 : 0),
            .uint8(.msgFilterFriends, msgFilterFriends ? 1 : 0),
            .uint8(.msgFilterSecure, msgFilterSecure ? 1 : 0),
            .uint8(.msgFilterByKeyword, msgFilterByKeyword ? 1 : 0),
            .string(.msgFilterKeywords, msgFilterKeywords),
        ]
        tags.append(msg)

        var sig = ECTag.empty(.prefsOnlineSig)
        sig.children = [.uint8(.onlineSigEnabled, onlineSigEnabled ? 1 : 0)]
        tags.append(sig)

        var sec = ECTag.empty(.prefsSecurity)
        sec.children = [
            .number(.securityCanSeeShares, canSeeShares),
            .uint8(.ipfilterClients, ipfilterClients ? 1 : 0),
            .uint8(.ipfilterServers, ipfilterServers ? 1 : 0),
            .uint8(.ipfilterAutoUpdate, ipfilterAutoUpdate ? 1 : 0),
            .string(.ipfilterUpdateURL, ipfilterUpdateURL),
            .number(.ipfilterLevel, ipfilterLevel),
            .uint8(.ipfilterFilterLAN, ipfilterFilterLAN ? 1 : 0),
            .uint8(.securityUseSecIdent, useSecIdent ? 1 : 0),
            .uint8(.securityObfuscationSupported, obfuscationSupported ? 1 : 0),
            .uint8(.securityObfuscationRequested, obfuscationRequested ? 1 : 0),
            .uint8(.securityObfuscationRequired, obfuscationRequired ? 1 : 0),
        ]
        tags.append(sec)

        var tweaks = ECTag.empty(.prefsCoreTweaks)
        tweaks.children = [
            .number(.coretwMaxConnPerFive, maxConnPerFive),
            .number(.coretwFileBuffer, fileBufferSize),
            .number(.coretwULQueue, uploadQueueSize),
            .number(.coretwSrvKeepaliveTimeout, serverKeepAliveTimeout),
        ]
        tags.append(tweaks)

        var web = ECTag.empty(.prefsRemoteCtrl)
        web.children = [
            .uint8(.webserverAutorun, webserverAutorun ? 1 : 0),
            .number(.webserverPort, webserverPort),
            .uint8(.webserverGuest, webserverGuest ? 1 : 0),
            .uint8(.webserverUseGzip, webserverUseGzip ? 1 : 0),
            .number(.webserverRefresh, webserverRefresh),
        ]
        tags.append(web)

        var kad = ECTag.empty(.prefsKademlia)
        kad.children = [.string(.kademliaUpdateURL, kadUpdateURL)]
        tags.append(kad)

        if directoriesLoaded {
            var dirs = ECTag.empty(.prefsDirectories)
            var sharedTag = ECTag.number(.directoriesShared, UInt64(sharedDirs.count))
            sharedTag.children = sharedDirs.map { .string(.string, $0) }
            dirs.children = [
                .string(.directoriesIncoming, dirIncoming),
                .string(.directoriesTemp, dirTemp),
                sharedTag,
                .uint8(.directoriesShareHidden, shareHidden ? 1 : 0),
                .uint8(.directoriesAutoRescan, autoRescanShared ? 1 : 0),
            ]
            tags.append(dirs)
        }

        return ECPacket(.setPreferences, tags: tags)
    }
}
