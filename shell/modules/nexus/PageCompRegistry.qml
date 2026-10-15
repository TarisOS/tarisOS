// Copyright (C) 2026 George Dobreff ("Witcher") and contributors
// SPDX-License-Identifier: GPL-3.0-only

pragma Singleton

import QtQuick
import QtQuick.Layouts
import Taris.Config
import Taris.I18n
import qs.components
import qs.services
import qs.modules.nexus.common
import qs.modules.nexus.pages
import qs.modules.nexus.pages.apps
import qs.modules.nexus.pages.audio
import qs.modules.nexus.pages.bluetooth
import qs.modules.nexus.pages.network
import qs.modules.nexus.pages.panels
import qs.modules.nexus.pages.services
import qs.modules.nexus.pages.wallandstyle
import qs.modules.nexus.pages.panels.taskbar

QtObject {
    id: root

    // The sidebar's pages (PageRegistry.pages): allPageComps without what PageRegistry doesn't show
    readonly property list<Component> pageComps: allPageComps.filter((c, i) => PageRegistry.shows(PageRegistry.allPages[i]))

    // In PageRegistry.allPages' order
    readonly property list<Component> allPageComps: [
        // Connectivity
        Component {
            // Network
            StackPage {
                Component {
                    NetworkPage {}
                }
                Component {
                    EthernetDetailPage {}
                }
                Component {
                    AddNetworkPage {}
                }
                Component {
                    NetworkDetailPage {}
                }
                Component {
                    AddVpnPage {}
                }
                Component {
                    AllNetworksPage {}
                }
                Component {
                    SavedNetworksPage {}
                }
                Component {
                    TorPage {}
                }
            }
        },
        Component {
            // Bluetooth
            StackPage {
                Component {
                    BluetoothPage {}
                }
                Component {
                    BtDeviceInfo {}
                }
                Component {
                    BluetoothPairing {}
                }
            }
        },
        // General, look, panels, displays and power
        Component {
            // General (merged: About, Updates, Language & region), with Updates' sub-page in the
            // same place
            StackPage {
                Component {
                    GeneralPage {}
                }
                Component {
                    UpdatesListPage {}
                }
            }
        },
        Component {
            StackPage {
                Component {
                    AboutPage {}
                }
            }
        },
        Component {
            // Updates
            StackPage {
                Component {
                    UpdatesPage {}
                }
                Component {
                    UpdatesListPage {}
                }
            }
        },
        Component {
            // Language & region
            StackPage {
                Component {
                    LanguageAndRegion {}
                }
            }
        },
        Component {
            // Appearance (merged: Wallpaper & style, Window style), with Wallpaper & style's
            // sub-pages in the same places
            StackPage {
                Component {
                    AppearancePage {}
                }
                Component {
                    WallpaperSelect {}
                }
                Component {
                    WallpaperCategory {}
                }
                Component {
                    ColourSelect {}
                }
            }
        },
        Component {
            // Wallpaper & style
            StackPage {
                Component {
                    WallpaperAndStyle {}
                }
                Component {
                    WallpaperSelect {}
                }
                Component {
                    WallpaperCategory {}
                }
                Component {
                    ColourSelect {}
                }
            }
        },
        Component {
            // Window style
            StackPage {
                Component {
                    WindowStylePage {}
                }
            }
        },
        Component {
            // Panels
            StackPage {
                Component {
                    PanelsPage {}
                }
                Component {
                    DashboardPanel {}
                }
                Component {
                    TaskbarPanel {}
                }
                Component {
                    LauncherPanel {}
                }
                Component {
                    UtilitiesPanel {}
                }

                // Taskbar component sub-pages
                Component {
                    BarWorkspaces {}
                }
                Component {
                    BarTray {}
                }
                Component {
                    BarStatusIcons {}
                }
                Component {
                    BarClock {}
                }

                // Dock (PageRegistry: in Panels while consolidated)
                Component {
                    DockPage {
                        isSubPage: true
                    }
                }

                // The notifications sidebar
                Component {
                    SidebarPanel {}
                }
            }
        },
        Component {
            // Dock
            StackPage {
                Component {
                    DockPage {}
                }
            }
        },
        Component {
            // Displays
            StackPage {
                Component {
                    DisplaysPage {}
                }
            }
        },
        Component {
            // Power
            StackPage {
                Component {
                    PowerPage {}
                }
            }
        },
        // Notifications and sound
        Component {
            // Services
            StackPage {
                Component {
                    ServicesPage {}
                }
                Component {
                    NotificationsPage {}
                }
            }
        },
        Component {
            // Audio
            StackPage {
                Component {
                    AudioPage {}
                }
                Component {
                    AppVolumes {}
                }
            }
        },
        // Security
        Component {
            // Security
            StackPage {
                Component {
                    SecurityPage {}
                }
            }
        },
        Component {
            // Backup & restore
            StackPage {
                Component {
                    BackupPage {}
                }
            }
        },
        // Input
        Component {
            // Keyboard & trackpad
            StackPage {
                Component {
                    KeyboardPage {}
                }
            }
        },
        // Apps and plugins
        Component {
            // Apps
            StackPage {
                Component {
                    AppsPage {}
                }
                Component {
                    AllApps {}
                }
                Component {
                    AppInfo {}
                }
            }
        },
        Component {
            PlaceholderComp {}
        }
    ]

    readonly property Component placeholderComp: Component {
        PlaceholderComp {}
    }

    component PlaceholderComp: Item {
        property NexusState nState // To avoid the warning from non-existent property

        ColumnLayout {
            anchors.centerIn: parent
            spacing: Tokens.padding.extraSmall

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: "handyman"
                color: Colours.palette.m3outlineVariant
                fontStyle: Tokens.font.icon.extraLarge
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Tr.tr("Page under construction")
                color: Colours.palette.m3outlineVariant
                font: Tokens.font.title.large
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Tr.tr("This page will be available in a future update.")
                color: Colours.palette.m3outlineVariant
                font: Tokens.font.body.large
            }
        }
    }
}
