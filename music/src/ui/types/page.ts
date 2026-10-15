// Written for TarisOS (Taris Music) by George Dobreff ("Witcher") and contributors, 2026.
import type { Album, Artist, Playlist, SearchResults, Track } from "../../datasource/types";

export type PageView = "home" | "album" | "artist" | "playlist" | "related" | "search" | "history" | "browse" | "library";

/** What a page shows: the part of a page that back and forward move between. */
export interface PageState {
  title?: string;
  view: PageView;
  /** Which Browse tab to open on. Only meaningful when `view` is "browse". */
  browseTab?: string;
  album?: Album;
  artist?: Artist;
  playlist?: Playlist;
  /** The track a "related" view is about. */
  relatedTrack?: Track;
  searchQuery?: string;
  searchResults?: Track[];
  mixedSearchResults?: SearchResults;
  searchLoading?: boolean;
}

export interface PageHistory {
  back: PageState[];
  forward: PageState[];
}

/** The page on screen, with where back and forward lead. */
export interface Page extends PageState {
  isQueueOpen?: boolean;
  navigationHistory?: PageHistory;
}
