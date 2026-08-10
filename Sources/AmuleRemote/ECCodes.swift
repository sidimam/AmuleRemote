// EC (External Connection) protocol constants — from aMule ECCodes.abstract, protocol 0x0204.
import Foundation

enum EC {
    static let protocolVersion: UInt16 = 0x0204

    // Transmission-layer flags
    static let flagZlib: UInt32 = 0x00000001
    static let flagUTF8Numbers: UInt32 = 0x00000002
    static let flagLargeTagCount: UInt32 = 0x00000010
    static let flagBase: UInt32 = 0x00000020
}

enum ECOp: UInt8 {
    case noop = 0x01
    case authReq = 0x02
    case authFail = 0x03
    case authOK = 0x04
    case failed = 0x05
    case strings = 0x06
    case miscData = 0x07
    case shutdown = 0x08
    case addLink = 0x09
    case statReq = 0x0A
    case getConnState = 0x0B
    case stats = 0x0C
    case getDloadQueue = 0x0D
    case getUloadQueue = 0x0E
    case getSharedFiles = 0x10
    case sharedSetPrio = 0x11
    case partfileSwapA4AFThis = 0x16
    case partfileSwapA4AFThisAuto = 0x17
    case partfileSwapA4AFOthers = 0x18
    case partfilePause = 0x19
    case partfileResume = 0x1A
    case partfileStop = 0x1B
    case partfilePrioSet = 0x1C
    case partfileDelete = 0x1D
    case partfileSetCat = 0x1E
    case dloadQueue = 0x1F
    case uloadQueue = 0x20
    case sharedFiles = 0x22
    case sharedFilesReload = 0x23
    case renameFile = 0x25
    case searchStart = 0x26
    case searchStop = 0x27
    case searchResults = 0x28
    case searchProgress = 0x29
    case downloadSearchResult = 0x2A
    case ipfilterReload = 0x2B
    case getServerList = 0x2C
    case serverList = 0x2D
    case serverDisconnect = 0x2E
    case serverConnect = 0x2F
    case serverRemove = 0x30
    case serverAdd = 0x31
    case serverUpdateFromURL = 0x32
    case addLogLine = 0x33
    case addDebugLogLine = 0x34
    case getLog = 0x35
    case getDebugLog = 0x36
    case getServerInfo = 0x37
    case log = 0x38
    case debugLog = 0x39
    case serverInfo = 0x3A
    case resetLog = 0x3B
    case resetDebugLog = 0x3C
    case clearServerInfo = 0x3D
    case getLastLogEntry = 0x3E
    case getPreferences = 0x3F
    case setPreferences = 0x40
    case createCategory = 0x41
    case updateCategory = 0x42
    case deleteCategory = 0x43
    case getStatsGraphs = 0x44
    case statsGraphs = 0x45
    case getStatsTree = 0x46
    case statsTree = 0x47
    case kadStart = 0x48
    case kadStop = 0x49
    case connect = 0x4A
    case disconnect = 0x4B
    case kadUpdateFromURL = 0x4D
    case kadBootstrapFromIP = 0x4E
    case authSalt = 0x4F
    case authPasswd = 0x50
    case ipfilterUpdate = 0x51
    case getUpdate = 0x52
    case clearCompleted = 0x53
    case clientSwapToAnotherFile = 0x54
    case sharedFileSetComment = 0x55
    case serverSetStaticPrio = 0x56
    case friend = 0x57
}

enum ECTagName: UInt16 {
    case string = 0x0000
    case passwdHash = 0x0001
    case protocolVersion = 0x0002
    case versionID = 0x0003
    case detailLevel = 0x0004
    case connState = 0x0005
    case ed2kID = 0x0006
    case logToStatus = 0x0007
    case bootstrapIP = 0x0008
    case bootstrapPort = 0x0009
    case clientID = 0x000A
    case passwdSalt = 0x000B
    case canZlib = 0x000C
    case canUTF8Numbers = 0x000D
    case canNotify = 0x000E
    case ecid = 0x000F
    case kadID = 0x0010
    case canLargeTagCount = 0x0011
    case canPartialUpdate = 0x0012
    case fileRemoved = 0x0013
    case preferNoZlib = 0x0014

    case clientName = 0x0100
    case clientVersion = 0x0101
    case clientMod = 0x0102

    case statsULSpeed = 0x0200
    case statsDLSpeed = 0x0201
    case statsULSpeedLimit = 0x0202
    case statsDLSpeedLimit = 0x0203
    case statsUpOverhead = 0x0204
    case statsDownOverhead = 0x0205
    case statsTotalSrcCount = 0x0206
    case statsBannedCount = 0x0207
    case statsULQueueLen = 0x0208
    case statsED2KUsers = 0x0209
    case statsKadUsers = 0x020A
    case statsED2KFiles = 0x020B
    case statsKadFiles = 0x020C
    case statsLoggerMessage = 0x020D
    case statsKadFirewalledUDP = 0x020E
    case statsKadIndexedSources = 0x020F
    case statsKadIndexedKeywords = 0x0210
    case statsKadIndexedNotes = 0x0211
    case statsKadIndexedLoad = 0x0212
    case statsKadIPAddress = 0x0213
    case statsBuddyStatus = 0x0214
    case statsBuddyIP = 0x0215
    case statsBuddyPort = 0x0216
    case statsKadInLANMode = 0x0217
    case statsTotalSentBytes = 0x0218
    case statsTotalReceivedBytes = 0x0219
    case statsSharedFileCount = 0x021A
    case statsKadNodes = 0x021B

    case partfile = 0x0300
    case partfileName = 0x0301
    case partfilePartmetID = 0x0302
    case partfileSizeFull = 0x0303
    case partfileSizeXfer = 0x0304
    case partfileSizeXferUp = 0x0305
    case partfileSizeDone = 0x0306
    case partfileSpeed = 0x0307
    case partfileStatus = 0x0308
    case partfilePrio = 0x0309
    case partfileSourceCount = 0x030A
    case partfileSourceCountA4AF = 0x030B
    case partfileSourceCountNotCurrent = 0x030C
    case partfileSourceCountXfer = 0x030D
    case partfileED2KLink = 0x030E
    case partfileCat = 0x030F
    case partfileLastRecv = 0x0310
    case partfileLastSeenComp = 0x0311
    case partfilePartStatus = 0x0312
    case partfileGapStatus = 0x0313
    case partfileReqStatus = 0x0314
    case partfileSourceNames = 0x0315
    case partfileComments = 0x0316
    case partfileStopped = 0x0317
    case partfileDownloadActive = 0x0318
    case partfileLostCorruption = 0x0319
    case partfileGainedCompression = 0x031A
    case partfileSavedICH = 0x031B
    case partfileSourceNamesCounts = 0x031C
    case partfileAvailableParts = 0x031D
    case partfileHash = 0x031E
    case partfileShared = 0x031F
    case partfileHashedPartCount = 0x0320
    case partfileA4AFAuto = 0x0321
    case partfileA4AFSources = 0x0322

    case knownfile = 0x0400
    case knownfileXferred = 0x0401
    case knownfileXferredAll = 0x0402
    case knownfileReqCount = 0x0403
    case knownfileReqCountAll = 0x0404
    case knownfileAcceptCount = 0x0405
    case knownfileAcceptCountAll = 0x0406
    case knownfileAICHMasterhash = 0x0407
    case knownfileFilename = 0x0408
    case knownfileCompleteSourcesLow = 0x0409
    case knownfileCompleteSourcesHigh = 0x040A
    case knownfilePrio = 0x040B
    case knownfileOnQueue = 0x040C
    case knownfileCompleteSources = 0x040D
    case knownfileComment = 0x040E
    case knownfileRating = 0x040F

    case server = 0x0500
    case serverName = 0x0501
    case serverDesc = 0x0502
    case serverAddress = 0x0503
    case serverPing = 0x0504
    case serverUsers = 0x0505
    case serverUsersMax = 0x0506
    case serverFiles = 0x0507
    case serverPrio = 0x0508
    case serverFailed = 0x0509
    case serverStatic = 0x050A
    case serverVersion = 0x050B
    case serverIP = 0x050C
    case serverPort = 0x050D

    case client = 0x0600
    case clientSoftware = 0x0601
    case clientScore = 0x0602
    case clientHash = 0x0603
    case clientFriendSlot = 0x0604
    case clientWaitTime = 0x0605
    case clientXferTime = 0x0606
    case clientQueueTime = 0x0607
    case clientLastTime = 0x0608
    case clientUploadSession = 0x0609
    case clientUploadTotal = 0x060A
    case clientDownloadTotal = 0x060B
    case clientDownloadState = 0x060C
    case clientUpSpeed = 0x060D
    case clientDownSpeed = 0x060E
    case clientFrom = 0x060F
    case clientUserIP = 0x0610
    case clientUserPort = 0x0611
    case clientServerIP = 0x0612
    case clientServerPort = 0x0613
    case clientServerName = 0x0614
    case clientSoftVerStr = 0x0615
    case clientWaitingPosition = 0x0616
    case clientIdentState = 0x0617
    case clientObfuscationStatus = 0x0618
    case clientRemoteQueueRank = 0x061A
    case clientDisableViewShared = 0x061B
    case clientUploadState = 0x061C
    case clientExtProtocol = 0x061D
    case clientUserID = 0x061E
    case clientUploadFile = 0x061F
    case clientRequestFile = 0x0620
    case clientA4AFFiles = 0x0621
    case clientOldRemoteQueueRank = 0x0622
    case clientKadPort = 0x0623
    case clientPartStatus = 0x0624
    case clientNextRequestedPart = 0x0625
    case clientLastDownloadingPart = 0x0626
    case clientRemoteFilename = 0x0627
    case clientModVersion = 0x0628
    case clientOSInfo = 0x0629
    case clientAvailableParts = 0x062A
    case clientUploadPartStatus = 0x062B

    case searchFile = 0x0700
    case searchType = 0x0701
    case searchName = 0x0702
    case searchMinSize = 0x0703
    case searchMaxSize = 0x0704
    case searchFileType = 0x0705
    case searchExtension = 0x0706
    case searchAvailability = 0x0707
    case searchStatus = 0x0708
    case searchParent = 0x0709

    case selectPrefs = 0x1000

    case prefsCategories = 0x1100
    case category = 0x1101
    case categoryTitle = 0x1102
    case categoryPath = 0x1103
    case categoryComment = 0x1104
    case categoryColor = 0x1105
    case categoryPrio = 0x1106

    case prefsGeneral = 0x1200
    case userNick = 0x1201
    case userHash = 0x1202
    case userHost = 0x1203
    case generalCheckNewVersion = 0x1204

    case prefsConnections = 0x1300
    case connDLCap = 0x1301
    case connULCap = 0x1302
    case connMaxDL = 0x1303
    case connMaxUL = 0x1304
    case connSlotAllocation = 0x1305
    case connTCPPort = 0x1306
    case connUDPPort = 0x1307
    case connUDPDisable = 0x1308
    case connMaxFileSources = 0x1309
    case connMaxConn = 0x130A
    case connAutoconnect = 0x130B
    case connReconnect = 0x130C
    case networkED2K = 0x130D
    case networkKademlia = 0x130E

    case prefsMessageFilter = 0x1400
    case msgFilterEnabled = 0x1401
    case msgFilterAll = 0x1402
    case msgFilterFriends = 0x1403
    case msgFilterSecure = 0x1404
    case msgFilterByKeyword = 0x1405
    case msgFilterKeywords = 0x1406

    case prefsRemoteCtrl = 0x1500
    case webserverAutorun = 0x1501
    case webserverPort = 0x1502
    case webserverGuest = 0x1503
    case webserverUseGzip = 0x1504
    case webserverRefresh = 0x1505
    case webserverTemplate = 0x1506

    case prefsOnlineSig = 0x1600
    case onlineSigEnabled = 0x1601

    case prefsServers = 0x1700
    case serversRemoveDead = 0x1701
    case serversDeadServerRetries = 0x1702
    case serversAutoUpdate = 0x1703
    case serversURLList = 0x1704
    case serversAddFromServer = 0x1705
    case serversAddFromClient = 0x1706
    case serversUseScoreSystem = 0x1707
    case serversSmartIDCheck = 0x1708
    case serversSafeServerConnect = 0x1709
    case serversAutoconnStaticOnly = 0x170A
    case serversManualHighPrio = 0x170B
    case serversUpdateURL = 0x170C

    case prefsFiles = 0x1800
    case filesICHEnabled = 0x1801
    case filesAICHTrust = 0x1802
    case filesNewPaused = 0x1803
    case filesNewAutoDLPrio = 0x1804
    case filesPreviewPrio = 0x1805
    case filesNewAutoULPrio = 0x1806
    case filesULFullChunks = 0x1807
    case filesStartNextPaused = 0x1808
    case filesResumeSameCat = 0x1809
    case filesSaveSources = 0x180A
    case filesExtractMetadata = 0x180B
    case filesAllocFullSize = 0x180C
    case filesCheckFreeSpace = 0x180D
    case filesMinFreeSpace = 0x180E
    case filesCreateNormal = 0x180F

    case prefsDirectories = 0x1A00
    case directoriesIncoming = 0x1A01
    case directoriesTemp = 0x1A02
    case directoriesShared = 0x1A03
    case directoriesShareHidden = 0x1A04
    case directoriesAutoRescan = 0x1A05

    case prefsStatistics = 0x1B00
    case statsGraphWidth = 0x1B01
    case statsGraphScale = 0x1B02
    case statsGraphLast = 0x1B03
    case statsGraphData = 0x1B04
    case statTreeCapping = 0x1B05
    case statTreeNode = 0x1B06
    case statNodeValue = 0x1B07
    case statValueType = 0x1B08
    case statTreeNodeID = 0x1B09

    case prefsSecurity = 0x1C00
    case securityCanSeeShares = 0x1C01
    case ipfilterClients = 0x1C02
    case ipfilterServers = 0x1C03
    case ipfilterAutoUpdate = 0x1C04
    case ipfilterUpdateURL = 0x1C05
    case ipfilterLevel = 0x1C06
    case ipfilterFilterLAN = 0x1C07
    case securityUseSecIdent = 0x1C08
    case securityObfuscationSupported = 0x1C09
    case securityObfuscationRequested = 0x1C0A
    case securityObfuscationRequired = 0x1C0B

    case prefsCoreTweaks = 0x1D00
    case coretwMaxConnPerFive = 0x1D01
    case coretwVerbose = 0x1D02
    case coretwFileBuffer = 0x1D03
    case coretwULQueue = 0x1D04
    case coretwSrvKeepaliveTimeout = 0x1D05

    case prefsKademlia = 0x1E00
    case kademliaUpdateURL = 0x1E01
}

enum ECTagType: UInt8 {
    case unknown = 0
    case custom = 1
    case uint8 = 2
    case uint16 = 3
    case uint32 = 4
    case uint64 = 5
    case string = 6
    case double = 7
    case ipv4 = 8
    case hash16 = 9
    case uint128 = 10
}

enum ECDetailLevel: UInt8 {
    case cmd = 0x00
    case web = 0x01
    case full = 0x02
    case update = 0x03
    case incUpdate = 0x04
}

enum ECSearchType: UInt8, CaseIterable, Identifiable {
    case local = 0x00
    case global = 0x01
    case kad = 0x02

    var id: UInt8 { rawValue }
    var label: String {
        switch self {
        case .local: return "Locale"
        case .global: return "Globale (server)"
        case .kad: return "Kademlia"
        }
    }
}

// EC_PREFS_* selection bitmask
enum ECPrefs {
    static let categories: UInt32 = 0x00000001
    static let general: UInt32 = 0x00000002
    static let connections: UInt32 = 0x00000004
    static let messageFilter: UInt32 = 0x00000008
    static let remoteControls: UInt32 = 0x00000010
    static let onlineSig: UInt32 = 0x00000020
    static let servers: UInt32 = 0x00000040
    static let files: UInt32 = 0x00000080
    static let directories: UInt32 = 0x00000200
    static let statistics: UInt32 = 0x00000400
    static let security: UInt32 = 0x00000800
    static let coreTweaks: UInt32 = 0x00001000
    static let kademlia: UInt32 = 0x00002000
    static let all: UInt32 = 0xFFFFFFFF
}
