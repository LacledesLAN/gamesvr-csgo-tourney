/**
 * =============================================================================
 * Get5 web API integration
 * Copyright (C) 2016. Sean Lewis.  All rights reserved.
 * =============================================================================
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "include/get5.inc"
#include "include/logdebug.inc"
#include <cstrike>
#include <sourcemod>

#include "get5/util.sp"
#include "get5/version.sp"

#include <SteamWorks>
#include <json>  // github.com/clugg/sm-json

#include "get5/jsonhelpers.sp"

#pragma semicolon 1
#pragma newdecls required

ConVar g_UseSVGCvar;
char g_LogoBasePath[128];
ConVar g_APIKeyCvar;
char g_APIKey[128];

ConVar g_APIURLCvar;
char g_APIURL[128];

#define LOGO_DIR        "materials/panorama/images/tournaments/teams"
#define LEGACY_LOGO_DIR "resource/flash/econ/tournaments/teams"

// clang-format off
public Plugin myinfo = {
  name = "Get5 Web API Integration",
  author = "splewis",
  description = "Records match stats to a get5-web api",
  version = PLUGIN_VERSION,
  url = "https://github.com/splewis/get5"
};
// clang-format on

public void OnPluginStart() {
  InitDebugLog("get5_debug", "get5_api");
  LogDebug("OnPluginStart version=%s", PLUGIN_VERSION);
  g_UseSVGCvar = CreateConVar("get5_use_svg", "1", "support svg team logos");
  HookConVarChange(g_UseSVGCvar, LogoBasePathChanged);
  g_LogoBasePath = g_UseSVGCvar.BoolValue ? LOGO_DIR : LEGACY_LOGO_DIR;
  g_APIKeyCvar = CreateConVar("get5_web_api_key", "", "Match API key, this is automatically set through rcon");
  HookConVarChange(g_APIKeyCvar, ApiInfoChanged);

  g_APIURLCvar = CreateConVar("get5_web_api_url", "", "URL the get5 api is hosted at");

  HookConVarChange(g_APIURLCvar, ApiInfoChanged);

  RegConsoleCmd("get5_web_available", Command_Available);
}

static Action Command_Available(int client, int args) {
  char versionString[64] = "unknown";
  ConVar versionCvar = FindConVar("get5_version");
  if (versionCvar != null) {
    versionCvar.GetString(versionString, sizeof(versionString));
  }

  JSON_Object json = new JSON_Object();

  json.SetInt("gamestate", view_as<int>(Get5_GetGameState()));
  json.SetInt("available", 1);
  json.SetString("plugin_version", versionString);

  char buffer[256];
  json.Encode(buffer, sizeof(buffer), true);
  ReplyToCommand(client, buffer);

  json_cleanup_and_delete(json);

  return Plugin_Handled;
}

void LogoBasePathChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
  g_LogoBasePath = g_UseSVGCvar.BoolValue ? LOGO_DIR : LEGACY_LOGO_DIR;
}

void ApiInfoChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
  g_APIKeyCvar.GetString(g_APIKey, sizeof(g_APIKey));
  g_APIURLCvar.GetString(g_APIURL, sizeof(g_APIURL));

  // Add a trailing backslash to the api url if one is missing.
  int len = strlen(g_APIURL);
  if (len > 0 && g_APIURL[len - 1] != '/') {
    StrCat(g_APIURL, sizeof(g_APIURL), "/");
  }

  LogDebug("get5_web_api_url now set to %s", g_APIURL);
}

static Handle CreateRequest(EHTTPMethod httpMethod, const char[] apiMethod, any...) {
  char url[1024];
  FormatEx(url, sizeof(url), "%s%s", g_APIURL, apiMethod);

  char formattedUrl[1024];
  VFormat(formattedUrl, sizeof(formattedUrl), url, 3);

  LogDebug("Trying to create request to url %s", formattedUrl);

  Handle req = SteamWorks_CreateHTTPRequest(httpMethod, formattedUrl);
  if (StrEqual(g_APIKey, "")) {
    // Not using a web interface.
    return INVALID_HANDLE;

  } else if (req == INVALID_HANDLE) {
    LogError("Failed to create request to %s", formattedUrl);
    return INVALID_HANDLE;

  } else {
    SteamWorks_SetHTTPCallbacks(req, RequestCallback);
    AddStringParam(req, "key", g_APIKey);
    return req;
  }
}

void RequestCallback(Handle request, bool failure, bool requestSuccessful, EHTTPStatusCode statusCode) {
  if (failure || !requestSuccessful) {
    LogError("API request failed, HTTP status code = %d", statusCode);
    char response[1024];
    SteamWorks_GetHTTPResponseBodyData(request, response, sizeof(response));
    LogError(response);
  }
}

public void Get5_OnSeriesInit(const Get5SeriesStartedEvent event) {
  // Handle new logos.
  if (!DirExists(g_LogoBasePath)) {
    if (!CreateDirectory(g_LogoBasePath, 755)) {
      LogError("Failed to create logo directory: %s", g_LogoBasePath);
    }
  }

  char logo1[32];
  char logo2[32];
  GetConVarStringSafe("mp_teamlogo_1", logo1, sizeof(logo1));
  GetConVarStringSafe("mp_teamlogo_2", logo2, sizeof(logo2));
  CheckForLogo(logo1);
  CheckForLogo(logo2);
}

static void CheckForLogo(const char[] logo) {
  if (StrEqual(logo, "")) {
    return;
  }

  char logoPath[PLATFORM_MAX_PATH + 1];
  // change png to svg because it's better supported
  if (g_UseSVGCvar.BoolValue) {
    FormatEx(logoPath, sizeof(logoPath), "%s/%s.svg", g_LogoBasePath, logo);
  } else {
    FormatEx(logoPath, sizeof(logoPath), "%s/%s.png", g_LogoBasePath, logo);
  }

  // Try to fetch the file if we don't have it.
  if (!FileExists(logoPath)) {
    LogDebug("Fetching logo for %s", logo);
    Handle req = g_UseSVGCvar.BoolValue ? CreateRequest(k_EHTTPMethodGET, "/static/img/logos/%s.svg", logo)
                                        : CreateRequest(k_EHTTPMethodGET, "/static/img/logos/%s.png", logo);

    if (req == INVALID_HANDLE) {
      return;
    }

    Handle pack = CreateDataPack();
    WritePackString(pack, logo);

    SteamWorks_SetHTTPRequestContextValue(req, view_as<int>(pack));
    SteamWorks_SetHTTPCallbacks(req, LogoCallback);
    SteamWorks_SendHTTPRequest(req);
  }
}

static void LogoCallback(Handle request, bool failure, bool successful, EHTTPStatusCode status, int data) {
  if (failure || !successful) {
    LogError("Logo request failed, status code = %d", status);
    return;
  }

  DataPack pack = view_as<DataPack>(data);
  pack.Reset();
  char logo[32];
  pack.ReadString(logo, sizeof(logo));

  char logoPath[PLATFORM_MAX_PATH + 1];
  if (g_UseSVGCvar.BoolValue) {
    FormatEx(logoPath, sizeof(logoPath), "%s/%s.svg", g_LogoBasePath, logo);
  } else {
    FormatEx(logoPath, sizeof(logoPath), "%s/%s.png", g_LogoBasePath, logo);
  }

  LogMessage("Saved logo for %s to %s", logo, logoPath);
  SteamWorks_WriteHTTPResponseBodyToFile(request, logoPath);
}

public void Get5_OnGoingLive(const Get5GoingLiveEvent event) {
  char mapName[64];
  GetCurrentMap(mapName, sizeof(mapName));

  char matchId[64];
  event.GetMatchId(matchId, sizeof(matchId));

  Handle req = CreateRequest(k_EHTTPMethodPOST, "match/%s/map/%d/start", matchId, event.MapNumber);
  if (req != INVALID_HANDLE) {
    AddStringParam(req, "mapname", mapName);
    SteamWorks_SendHTTPRequest(req);
  }

  Get5_AddLiveCvar("get5_web_api_key", g_APIKey);
  Get5_AddLiveCvar("get5_web_api_url", g_APIURL);
}

static void UpdateRoundStats(const char[] matchId, const int mapNumber) {
  int t1score = CS_GetTeamScore(Get5_Get5TeamToCSTeam(Get5Team_1));
  int t2score = CS_GetTeamScore(Get5_Get5TeamToCSTeam(Get5Team_2));

  Handle req = CreateRequest(k_EHTTPMethodPOST, "match/%s/map/%d/update", matchId, mapNumber);
  if (req != INVALID_HANDLE) {
    AddIntParam(req, "team1score", t1score);
    AddIntParam(req, "team2score", t2score);
    SteamWorks_SendHTTPRequest(req);
  }

  KeyValues kv = new KeyValues("Stats");
  Get5_GetMatchStats(kv);
  char mapKey[32];
  FormatEx(mapKey, sizeof(mapKey), "map%d", mapNumber);
  if (kv.JumpToKey(mapKey)) {
    if (kv.JumpToKey("team1")) {
      if (kv.JumpToKey("players")) {
        UpdatePlayerStats(matchId, mapNumber, kv, Get5Team_1);
        kv.GoBack();
      }
      kv.GoBack();
    }
    if (kv.JumpToKey("team2")) {
      if (kv.JumpToKey("players")) {
        UpdatePlayerStats(matchId, mapNumber, kv, Get5Team_2);
        kv.GoBack();
      }
      kv.GoBack();
    }
    kv.GoBack();
  }
  delete kv;
}

public void Get5_OnMapResult(const Get5MapResultEvent event) {
  char matchId[64];
  event.GetMatchId(matchId, sizeof(matchId));

  char winnerString[64];
  GetTeamString(event.Winner.Team, winnerString, sizeof(winnerString));

  Handle req = CreateRequest(k_EHTTPMethodPOST, "match/%s/map/%d/finish", matchId, event.MapNumber);
  if (req != INVALID_HANDLE) {
    AddIntParam(req, "team1score", event.Team1.Score);
    AddIntParam(req, "team2score", event.Team2.Score);
    AddStringParam(req, "winner", winnerString);
    SteamWorks_SendHTTPRequest(req);
  }
}

static void AddIntStat(Handle req, KeyValues kv, const char[] field) {
  AddIntParam(req, field, kv.GetNum(field));
}

static void UpdatePlayerStats(const char[] matchId, const int mapNumber, const KeyValues kv, const Get5Team team) {
  char name[MAX_NAME_LENGTH];
  char auth[AUTH_LENGTH];

  if (kv.GotoFirstSubKey()) {
    do {
      kv.GetSectionName(auth, sizeof(auth));
      kv.GetString("name", name, sizeof(name));
      char teamString[16];
      GetTeamString(team, teamString, sizeof(teamString));

      Handle req = CreateRequest(k_EHTTPMethodPOST, "match/%s/map/%d/player/%s/update", matchId, mapNumber, auth);
      if (req != INVALID_HANDLE) {
        AddStringParam(req, "team", teamString);
        AddStringParam(req, STAT_NAME, name);
        AddIntStat(req, kv, STAT_KILLS);
        AddIntStat(req, kv, STAT_DEATHS);
        AddIntStat(req, kv, STAT_ASSISTS);
        AddIntStat(req, kv, STAT_FLASHBANG_ASSISTS);
        AddIntStat(req, kv, STAT_TEAMKILLS);
        AddIntStat(req, kv, STAT_SUICIDES);
        AddIntStat(req, kv, STAT_DAMAGE);
        AddIntStat(req, kv, STAT_UTILITY_DAMAGE);
        AddIntStat(req, kv, STAT_ENEMIES_FLASHED);
        AddIntStat(req, kv, STAT_FRIENDLIES_FLASHED);
        AddIntStat(req, kv, STAT_KNIFE_KILLS);
        AddIntStat(req, kv, STAT_HEADSHOT_KILLS);
        AddIntStat(req, kv, STAT_ROUNDSPLAYED);
        AddIntStat(req, kv, STAT_BOMBPLANTS);
        AddIntStat(req, kv, STAT_BOMBDEFUSES);
        AddIntStat(req, kv, STAT_1K);
        AddIntStat(req, kv, STAT_2K);
        AddIntStat(req, kv, STAT_3K);
        AddIntStat(req, kv, STAT_4K);
        AddIntStat(req, kv, STAT_5K);
        AddIntStat(req, kv, STAT_V1);
        AddIntStat(req, kv, STAT_V2);
        AddIntStat(req, kv, STAT_V3);
        AddIntStat(req, kv, STAT_V4);
        AddIntStat(req, kv, STAT_V5);
        AddIntStat(req, kv, STAT_FIRSTKILL_T);
        AddIntStat(req, kv, STAT_FIRSTKILL_CT);
        AddIntStat(req, kv, STAT_FIRSTDEATH_T);
        AddIntStat(req, kv, STAT_FIRSTDEATH_CT);
        AddIntStat(req, kv, STAT_TRADEKILL);
        AddIntStat(req, kv, STAT_KAST);
        AddIntStat(req, kv, STAT_CONTRIBUTION_SCORE);
        AddIntStat(req, kv, STAT_MVP);
        SteamWorks_SendHTTPRequest(req);
      }

    } while (kv.GotoNextKey());
    kv.GoBack();
  }
}

static void AddStringParam(Handle request, const char[] key, const char[] value) {
  if (!SteamWorks_SetHTTPRequestGetOrPostParameter(request, key, value)) {
    LogError("Failed to add http param %s=%s", key, value);
  } else {
    LogDebug("Added param %s=%s to request", key, value);
  }
}

static void AddIntParam(Handle request, const char[] key, int value) {
  char buffer[32];
  IntToString(value, buffer, sizeof(buffer));
  AddStringParam(request, key, buffer);
}

public void Get5_OnSeriesResult(const Get5SeriesResultEvent event) {
  char matchId[64];
  event.GetMatchId(matchId, sizeof(matchId));

  char winnerString[64];
  GetTeamString(event.Winner.Team, winnerString, sizeof(winnerString));

  KeyValues kv = new KeyValues("Stats");
  Get5_GetMatchStats(kv);
  bool forfeit = kv.GetNum(STAT_SERIES_FORFEIT, 0) != 0;
  delete kv;

  Handle req = CreateRequest(k_EHTTPMethodPOST, "match/%s/finish", matchId);
  if (req != INVALID_HANDLE) {
    AddStringParam(req, "winner", winnerString);
    AddIntParam(req, "forfeit", forfeit);
    SteamWorks_SendHTTPRequest(req);
  }

  g_APIKeyCvar.SetString("");
}

public void Get5_OnRoundStatsUpdated(const Get5RoundStatsUpdatedEvent event) {
  if (Get5_GetGameState() == Get5State_Live) {
    char matchId[64];
    event.GetMatchId(matchId, sizeof(matchId));
    UpdateRoundStats(matchId, event.MapNumber);
  }
}
