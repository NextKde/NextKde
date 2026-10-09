import QtQml

// Deterministic sample data for the Phase 1 UI-shell milestone.
// Replace this object with C++ QAbstractItemModels at the integration stage.
QtObject {
    id: catalog

    readonly property var songs: [
        {
            title: "world étude",
            artist: "豊崎愛生",
            album: "world Étude / アルタイル",
            duration: "03:57",
            source: "Local"
        },
        {
            title: "Friend",
            artist: "玉置浩二",
            album: "ワインレッドの心",
            duration: "03:22",
            source: "Local"
        },
        {
            title: "IVORY TOWER (feat. SennaRin)",
            artist: "泽野弘之, SennaRin",
            album: "《龙族》动画OST",
            duration: "02:57",
            source: "Local"
        },
        {
            title: "摇摇欲坠",
            artist: "ZIV",
            album: "摇摇欲坠",
            duration: "03:34",
            source: "Local"
        },
        {
            title: "疲惫的爱",
            artist: "step.jad依加",
            album: "疲惫的爱",
            duration: "04:45",
            source: "Local"
        },
        {
            title: "R.",
            artist: "李子豪 (HtFR)、大喜",
            album: "R.",
            duration: "03:01",
            source: "Local"
        },
        {
            title: "别问很可怕",
            artist: "J.Sheon",
            album: "You'll Never Know",
            duration: "04:08",
            source: "Local"
        },
        {
            title: "无法抗拒的你",
            artist: "Maderlin Weng",
            album: "无法抗拒的你",
            duration: "05:01",
            source: "Local"
        },
        {
            title: "迷宫",
            artist: "step.jad依加",
            album: "迷宫",
            duration: "03:37",
            source: "Local"
        },
        {
            title: "bad soul",
            artist: "DEN",
            album: "OPDEN",
            duration: "03:08",
            source: "Local"
        }
    ]

    readonly property var albums: [
        {
            title: "world étude",
            artist: "豊崎愛生",
            count: "12 首歌曲",
            color: "#2d8fca"
        },
        {
            title: "Sounds of Summer",
            artist: "The Beach Boys",
            count: "20 首歌曲",
            color: "#eea72f"
        },
        {
            title: "ワインレッドの心",
            artist: "玉置浩二",
            count: "10 首歌曲",
            color: "#b55368"
        },
        {
            title: "疲惫的爱",
            artist: "step.jad依加",
            count: "8 首歌曲",
            color: "#7659a9"
        },
        {
            title: "OPDEN",
            artist: "DEN",
            count: "11 首歌曲",
            color: "#3c7a78"
        },
        {
            title: "You'll Never Know",
            artist: "J.Sheon",
            count: "9 首歌曲",
            color: "#bf7c43"
        }
    ]

    readonly property var artists: [
        {
            name: "豊崎愛生",
            subtitle: "8 张专辑 · 42 首歌曲"
        },
        {
            name: "The Beach Boys",
            subtitle: "4 张专辑 · 38 首歌曲"
        },
        {
            name: "玉置浩二",
            subtitle: "3 张专辑 · 21 首歌曲"
        },
        {
            name: "step.jad依加",
            subtitle: "2 张专辑 · 17 首歌曲"
        },
        {
            name: "ZIV",
            subtitle: "1 张专辑 · 12 首歌曲"
        },
        {
            name: "DEN",
            subtitle: "1 张专辑 · 11 首歌曲"
        }
    ]

    readonly property var playlists: [
        {
            title: "我的收藏",
            subtitle: "24 首歌曲",
            kind: "Local",
            color: "#3c8fd0"
        },
        {
            title: "新建歌单 1",
            subtitle: "8 首歌曲",
            kind: "Local",
            color: "#7b6fc2"
        },
        {
            title: "通勤精选",
            subtitle: "网络歌单 · 已保存",
            kind: "Remote",
            color: "#d68450"
        }
    ]

    // Mock data mirrors the sections present in the Figma Discover and
    // Playlist boards.  These are intentionally plain QVariant-compatible
    // objects so they can later be replaced by QAbstractItemModels without
    // changing the page contracts.
    readonly property var discoverAlbums: [
        { title: "Summer Sounds", artist: "The Beach Boys", color: "#f0ad2f", cover: 1 },
        { title: "Overexposed", artist: "Maroon 5", color: "#c94f9f", cover: 2 },
        { title: "Dreamland", artist: "Glass Animals", color: "#c08df4", cover: 3 },
        { title: "Modern Love", artist: "Yuvan Shankar Raja", color: "#41bca1", cover: 4 },
        { title: "Formula 1 Theme", artist: "Brian Tyler", color: "#22252a", cover: 5 },
        { title: "Ved", artist: "Ritviz", color: "#368dcc", cover: 6 }
    ]

    // Discover keeps search suggestions and daily song recommendations as
    // separate data contracts. The UI can therefore be switched to backend
    // models without treating an album tile as a playable track.
    readonly property var hotSearches: [
        "新歌推荐", "每日榜单", "华语精选", "欧美热歌", "日系治愈", "夜间氛围"
    ]

    readonly property var searchHistory: [
        "world étude", "IVORY TOWER", "R&B", "The Beach Boys", "轻音乐"
    ]

    readonly property var dailySongs: [
        { title: "Blue Hour", artist: "ListenFree Select", album: "Daily Mix", duration: "03:41", source: "Online", remoteUrl: "mock://daily/blue-hour", cover: 2 },
        { title: "Night Walk", artist: "Mellow Cities", album: "Afterglow", duration: "04:08", source: "Online", remoteUrl: "mock://daily/night-walk", cover: 3 },
        { title: "Glass Sea", artist: "Harbor Lights", album: "Still Water", duration: "03:26", source: "Online", remoteUrl: "mock://daily/glass-sea", cover: 4 },
        { title: "Soft Signal", artist: "Noon Radio", album: "Frequency", duration: "02:59", source: "Online", remoteUrl: "mock://daily/soft-signal", cover: 5 },
        { title: "Homebound", artist: "Ritviz", album: "Ved", duration: "03:52", source: "Online", remoteUrl: "mock://daily/homebound", cover: 6 },
        { title: "Summer Again", artist: "The Beach Boys", album: "Summer Sounds", duration: "03:17", source: "Online", remoteUrl: "mock://daily/summer-again", cover: 1 }
    ]

    // Previous / current / next playback context used by the Discover hero.
    // Each item carries its own presentation tint so a backend replacement can
    // derive the same field from album artwork without changing the page API.
    readonly property var discoverHeroTracks: [
        { title: "Summer Again", artist: "The Beach Boys", album: "Summer Sounds", duration: "03:17", source: "Online", remoteUrl: "mock://daily/summer-again", cover: 1, color: "#e4aa29" },
        { title: "Ved", artist: "Ritviz", album: "Ved", duration: "03:52", source: "Online", remoteUrl: "mock://daily/homebound", cover: 6, color: "#168bd1" },
        { title: "Glass Sea", artist: "Harbor Lights", album: "Still Water", duration: "03:26", source: "Online", remoteUrl: "mock://daily/glass-sea", cover: 4, color: "#37a78f" }
    ]

    readonly property var onlinePlaylists: [
        { title: "通勤精选", subtitle: "每日更新 · 32 首歌曲", color: "#3b98d0", cover: 1 },
        { title: "轻松爵士", subtitle: "Jazz · 48 首歌曲", color: "#8a72c8", cover: 2 },
        { title: "深夜氛围", subtitle: "Ambient · 25 首歌曲", color: "#4fae9a", cover: 3 },
        { title: "新歌速递", subtitle: "本周热门 · 60 首歌曲", color: "#d08363", cover: 4 },
        { title: "华语 R&B", subtitle: "编辑精选 · 40 首歌曲", color: "#438fc8", cover: 5 }
    ]

    readonly property var searchTabs: ["全部", "歌曲", "专辑", "艺术家", "歌单"]

    readonly property var lyrics: [
        {
            timeMs: 12000,
            en: "We were dancing through the midnight",
            zh: "我们在午夜时分起舞"
        },
        {
            timeMs: 26000,
            en: "Every shadow knows your name",
            zh: "每一道影子都记得你的名字"
        },
        {
            timeMs: 51000,
            en: "I can hear the silence calling",
            zh: "我听见寂静正在呼唤"
        },
        {
            timeMs: 78000,
            en: "Stay with me until the morning",
            zh: "请陪我直到清晨"
        },
        {
            timeMs: 104000,
            en: "Let the fading light surround us",
            zh: "让渐暗的光环绕着我们"
        },
        {
            timeMs: 132000,
            en: "We will find a way back home",
            zh: "我们会找到回家的路"
        }
    ]
}
