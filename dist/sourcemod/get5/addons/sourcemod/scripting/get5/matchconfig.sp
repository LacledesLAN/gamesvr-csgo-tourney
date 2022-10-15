#include <string>

#define REMOTE_CONFIG_PATTERN "remote_config%d.json"
#define CONFIG_MATCHID_DEFAULT ""  // empty string if no match ID defined in config.
#define CONFIG_MATCHTITLE_DEFAULT "Map {MAPNUMBER} of {MAXMAPS}"
#define CONFIG_PLAYERSPERTEAM_DEFAULT 5
#define CONFIG_COACHESPERTEAM_DEFAULT 2
#define CONFIG_MINPLAYERSTOREADY_DEFAULT 0
#define CONFIG_MINSPECTATORSTOREADY_DEFAULT 0
#define CONFIG_SPECTATORSNAME_DEFAULT "casters"
#define CONFIG_NUM_MAPSDEFAULT 3
#define CONFIG_SKIPVETO_DEFAULT false
#define CONFIG_CLINCH_SERIES_DEFAULT true
#define CONFIG_VETOFIRST_DEFAULT "team1"
#define CONFIG_SIDETYPE_DEFAULT "standard"

bool LoadMatchConfig(const char[] config, bool restoreBackup = false) {
  if (g_GameState != Get5State_None && !restoreBackup) {
    return false;
  }

  ResetReadyStatus();
  LOOP_TEAMS(team) {
    g_TeamSeriesScores[team] = 0;
    g_TeamReadyForUnpause[team] = false;
    g_TeamGivenStopCommand[team] = false;
    // We only reset these on a new game.
    // During restore we want to keep our
    // current pauses used.
    if (!restoreBackup) {
      g_TacticalPauseTimeUsed[team] = 0;
      g_TacticalPausesUsed[team] = 0;
      g_TechnicalPausesUsed[team] = 0;
    }
    ClearArray(GetTeamCoaches(team));
    ClearArray(GetTeamPlayers(team));
  }

  g_MatchID = "";
  g_ReadyTimeWaitingUsed = 0;
  g_HasKnifeRoundStarted = false;
  g_KnifeWinnerTeam = Get5Team_None;
  g_MapChangePending = false;
  g_MapNumber = 0;
  g_NumberOfMapsInSeries = 0;
  g_RoundNumber = -1;
  g_LastVetoTeam = Get5Team_2;
  g_MapPoolList.Clear();
  g_MapsLeftInVetoPool.Clear();
  g_MapsToPlay.Clear();
  g_MapSides.Clear();
  g_CvarNames.Clear();
  g_CvarValues.Clear();
  g_TeamScoresPerMap.Clear();

  g_WaitingForRoundBackup = false;
  g_LastGet5BackupCvar.SetString("");

  CloseCvarStorage(g_KnifeChangedCvars);
  CloseCvarStorage(g_MatchConfigChangedCvars);

  if (!LoadMatchFile(config)) {
    return false;
  }

  // Copy all the maps into the veto pool.
  char mapName[PLATFORM_MAX_PATH];
  for (int i = 0; i < g_MapPoolList.Length; i++) {
    g_MapPoolList.GetString(i, mapName, sizeof(mapName));
    g_MapsLeftInVetoPool.PushString(mapName);
    g_TeamScoresPerMap.Push(0);
    g_TeamScoresPerMap.Set(g_TeamScoresPerMap.Length - 1, 0, 0);
    g_TeamScoresPerMap.Set(g_TeamScoresPerMap.Length - 1, 0, 1);
  }

  if (g_NumberOfMapsInSeries > g_MapPoolList.Length) {
    MatchConfigFail("Cannot play a series of %d maps with a maplist of %d maps",
                    g_NumberOfMapsInSeries, g_MapPoolList.Length);
    return false;
  }

  if (g_SkipVeto) {
    // Copy the first k maps from the maplist to the final match maps.
    for (int i = 0; i < g_NumberOfMapsInSeries; i++) {
      g_MapPoolList.GetString(i, mapName, sizeof(mapName));
      g_MapsToPlay.PushString(mapName);

      // Push a map side if one hasn't been set yet.
      if (g_MapSides.Length < g_MapsToPlay.Length) {
        if (g_MatchSideType == MatchSideType_Standard ||
            g_MatchSideType == MatchSideType_AlwaysKnife) {
          g_MapSides.Push(SideChoice_KnifeRound);
        } else {
          g_MapSides.Push(SideChoice_Team1CT);
        }
      }
    }

    if (!restoreBackup) {
      ChangeState(Get5State_Warmup);
      // When restoring from backup, changelevel is called after loading the match config.
      g_MapPoolList.GetString(Get5_GetMapNumber(), mapName, sizeof(mapName));
      char currentMap[PLATFORM_MAX_PATH];
      GetCurrentMap(currentMap, sizeof(currentMap));
      if (!StrEqual(mapName, currentMap)) {
        ChangeMap(mapName);
      }
    }
  } else if (!restoreBackup) {
    ChangeState(Get5State_PreVeto);
  }

  if (g_GameState == Get5State_None) {
    // Make sure here that we don't run the code below in game state none, but also not overriding
    // PreVeto. Currently, this could happen if you restored a backup with skip_veto:false.
    ChangeState(Get5State_Warmup);
  }

  // Before we run the Get5_OnSeriesInit forward, we want to ensure that as much game state is set
  // as possible, so that any implementation reacting to that event/forward will have all the
  // natives return proper data. ExecuteMatchConfigCvars gets called twice because
  // ExecCfg(g_WarmupCfgCvar) also does it async, but we need it here as the team assigment below
  // depends on it. We set this one first as the others may depend on something changed in the match
  // cvars section.
  ExecuteMatchConfigCvars();
  SetMatchTeamCvars();
  LoadPlayerNames();
  AddTeamLogosToDownloadTable();
  SetStartingTeams();

  if (!restoreBackup) {
    ExecCfg(g_WarmupCfgCvar);
    StartWarmup();
    if (IsPaused()) {
      LogDebug("Match was paused when loading match config. Unpausing.");
      UnpauseGame(Get5Team_None);
    }

    Stats_InitSeries();

    Get5SeriesStartedEvent startEvent =
        new Get5SeriesStartedEvent(g_MatchID, g_TeamNames[Get5Team_1], g_TeamNames[Get5Team_2]);

    LogDebug("Calling Get5_OnSeriesInit");

    Call_StartForward(g_OnSeriesInit);
    Call_PushCell(startEvent);
    Call_Finish();

    EventLogger_LogAndDeleteEvent(startEvent);

    if (!g_CheckAuthsCvar.BoolValue &&
        (GetTeamPlayers(Get5Team_1).Length != 0 || GetTeamPlayers(Get5Team_2).Length != 0 ||
         GetTeamCoaches(Get5Team_1).Length != 0 || GetTeamCoaches(Get5Team_2).Length != 0)) {
      LogError(
          "Setting player auths in the \"players\" or \"coaches\" section has no impact with get5_check_auths 0");
    }

    // ExecuteMatchConfigCvars must be executed before we place players, as it might have
    // get5_check_auths 1. We must also have called SetStartingTeams to get the sides right. When
    // restoring from backup, assigning to teams is done after loading the match config as it
    // depends on the sides being set correctly by the backup, so we put it inside this "if" here.
    // When the match is loaded, we do not want to assign players on no team, as they may be in the
    // process of joining the server, which is the reason for the timer callback. This has caused
    // problems with players getting stuck on no team when using match config autoload, essentially
    // recreating the "coaching bug". Adding a second seems to solve this problem. We cannot just
    // skip team none, as players may also just be on the team selection menu when the match is
    // loaded, meaning they will never have a joingame hook, as it already happened, and we still
    // want those players placed.
    if (g_CheckAuthsCvar.BoolValue) {
      LOOP_CLIENTS(i) {
        if (IsPlayer(i)) {
          if (GetClientTeam(i) == CS_TEAM_NONE) {
            CreateTimer(1.0, Timer_PlacePlayerFromTeamNone, i, TIMER_FLAG_NO_MAPCHANGE);
          } else {
            CheckClientTeam(i);
          }
        }
      }
    }
  }

  strcopy(g_LoadedConfigFile, sizeof(g_LoadedConfigFile), config);

  Get5_MessageToAll("%t", "MatchConfigLoadedInfoMessage");
  return true;
}

static Action Timer_PlacePlayerFromTeamNone(Handle timer, int client) {
  if (g_GameState != Get5State_None && IsPlayer(client)) {
    CheckClientTeam(client);
  }
}

static bool LoadMatchFile(const char[] config) {
  Get5PreloadMatchConfigEvent event = new Get5PreloadMatchConfigEvent(config);

  LogDebug("Calling Get5_OnPreLoadMatchConfig()");

  Call_StartForward(g_OnPreLoadMatchConfig);
  Call_PushCell(event);
  Call_Finish();

  EventLogger_LogAndDeleteEvent(event);

  if (!FileExists(config)) {
    MatchConfigFail("Match config file doesn't exist: \"%s\"", config);
    return false;
  }

  if (IsJSONPath(config)) {
    JSON_Object json = json_read_from_file(config);
    if (json == null) {
      MatchConfigFail("Failed to read match config as JSON.");
      return false;
    }

    if (!LoadMatchFromJson(json)) {  // This prints its own error
      json_cleanup_and_delete(json);
      return false;
    }
    json_cleanup_and_delete(json);

  } else {
    // Assume its a key-values file.
    KeyValues kv = new KeyValues("Match");
    if (!kv.ImportFromFile(config)) {
      delete kv;
      MatchConfigFail("Failed to read match config as KV.");
      return false;
    }

    if (!LoadMatchFromKv(kv)) {  // This prints its own error
      delete kv;
      return false;
    }
    delete kv;
  }

  return true;
}

static void MatchConfigFail(const char[] reason, any...) {
  char buffer[512];
  VFormat(buffer, sizeof(buffer), reason, 2);
  LogError("Failed to load match config: %s", buffer);

  Get5LoadMatchConfigFailedEvent event = new Get5LoadMatchConfigFailedEvent(buffer);

  LogDebug("Calling Get5_OnLoadMatchConfigFailed()");

  Call_StartForward(g_OnLoadMatchConfigFailed);
  Call_PushCell(event);
  Call_Finish();

  EventLogger_LogAndDeleteEvent(event);
}

stock bool LoadMatchFromUrl(const char[] url, ArrayList paramNames = null,
                            ArrayList paramValues = null) {
  bool steamWorksAvaliable = LibraryExists("SteamWorks");

  char cleanedUrl[1024];
  strcopy(cleanedUrl, sizeof(cleanedUrl), url);
  ReplaceString(cleanedUrl, sizeof(cleanedUrl), "\"", "");
  strcopy(g_LoadedConfigUrl, sizeof(g_LoadedConfigUrl), cleanedUrl);

  if (steamWorksAvaliable) {
    // Add the protocol strings if missing (only http).
    if (StrContains(cleanedUrl, "http://") == -1 && StrContains(cleanedUrl, "https://") == -1) {
      Format(cleanedUrl, sizeof(cleanedUrl), "http://%s", cleanedUrl);
    }
    LogDebug("cleanedUrl (SteamWorks) = %s", cleanedUrl);
    Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, cleanedUrl);
    if (request == INVALID_HANDLE) {
      MatchConfigFail("Failed to create HTTP GET request");
      return false;
    }

    if (paramNames != null && paramValues != null) {
      if (paramNames.Length != paramValues.Length) {
        MatchConfigFail("request paramNames and paramValues size mismatch");
        return false;
      }

      char param[128];
      char value[128];
      for (int i = 0; i < paramNames.Length; i++) {
        paramNames.GetString(i, param, sizeof(param));
        paramValues.GetString(i, value, sizeof(value));
        SteamWorks_SetHTTPRequestGetOrPostParameter(request, param, value);
      }
    }

    SteamWorks_SetHTTPCallbacks(request, SteamWorks_OnMatchConfigReceived);
    SteamWorks_SendHTTPRequest(request);
    return true;

  } else {
    MatchConfigFail("SteamWorks extension is not available");
    return false;
  }
}

// SteamWorks HTTP callback for fetching a workshop collection
static int SteamWorks_OnMatchConfigReceived(Handle request, bool failure, bool requestSuccessful,
                                            EHTTPStatusCode statusCode, Handle data) {
  if (failure || !requestSuccessful) {
    MatchConfigFail("Steamworks GET request failed, HTTP status code = %d", statusCode);
    return;
  }

  char remoteConfig[PLATFORM_MAX_PATH];
  GetTempFilePath(remoteConfig, sizeof(remoteConfig), REMOTE_CONFIG_PATTERN);
  SteamWorks_WriteHTTPResponseBodyToFile(request, remoteConfig);
  LoadMatchConfig(remoteConfig);

  strcopy(g_LoadedConfigFile, sizeof(g_LoadedConfigFile), g_LoadedConfigUrl);
}

void WriteMatchToKv(KeyValues kv) {
  kv.SetString("matchid", g_MatchID);
  kv.SetNum("scrim", g_InScrimMode);
  kv.SetNum("skip_veto", g_SkipVeto);
  kv.SetNum("num_maps", g_NumberOfMapsInSeries);
  kv.SetNum("players_per_team", g_PlayersPerTeam);
  kv.SetNum("coaches_per_team", g_CoachesPerTeam);
  kv.SetNum("min_players_to_ready", g_MinPlayersToReady);
  kv.SetNum("min_spectators_to_ready", g_MinSpectatorsToReady);
  kv.SetString("match_title", g_MatchTitle);
  kv.SetNum("clinch_series", g_SeriesCanClinch);

  kv.SetNum("favored_percentage_team1", g_FavoredTeamPercentage);
  kv.SetString("favored_percentage_text", g_FavoredTeamText);

  char sideType[64];
  MatchSideTypeToString(g_MatchSideType, sideType, sizeof(sideType));
  kv.SetString("side_type", sideType);

  kv.JumpToKey("maplist", true);
  for (int i = 0; i < g_MapPoolList.Length; i++) {
    char map[PLATFORM_MAX_PATH];
    g_MapPoolList.GetString(i, map, sizeof(map));
    kv.SetString(map, KEYVALUE_STRING_PLACEHOLDER);
  }
  kv.GoBack();

  kv.JumpToKey("team1", true);
  AddTeamBackupData(kv, Get5Team_1);
  kv.GoBack();

  kv.JumpToKey("team2", true);
  AddTeamBackupData(kv, Get5Team_2);
  kv.GoBack();

  kv.JumpToKey("spectators", true);
  AddTeamBackupData(kv, Get5Team_Spec);
  kv.GoBack();

  kv.JumpToKey("cvars", true);
  for (int i = 0; i < g_CvarNames.Length; i++) {
    char cvarName[MAX_CVAR_LENGTH];
    char cvarValue[MAX_CVAR_LENGTH];
    g_CvarNames.GetString(i, cvarName, sizeof(cvarName));
    g_CvarValues.GetString(i, cvarValue, sizeof(cvarValue));
    kv.SetString(cvarName, cvarValue);
  }
  kv.GoBack();
}

static void AddTeamBackupData(KeyValues kv, Get5Team team) {
  kv.JumpToKey("players", true);
  char auth[AUTH_LENGTH];
  char name[MAX_NAME_LENGTH];
  for (int i = 0; i < GetTeamPlayers(team).Length; i++) {
    GetTeamPlayers(team).GetString(i, auth, sizeof(auth));
    if (!g_PlayerNames.GetString(auth, name, sizeof(name))) {
      strcopy(name, sizeof(name), KEYVALUE_STRING_PLACEHOLDER);
    }
    kv.SetString(auth, name);
  }
  kv.GoBack();

  kv.SetString("name", g_TeamNames[team]);
  if (team != Get5Team_Spec) {
    kv.SetString("tag", g_TeamTags[team]);
    kv.SetString("flag", g_TeamFlags[team]);
    kv.SetString("logo", g_TeamLogos[team]);
    kv.SetString("matchtext", g_TeamMatchTexts[team]);
    kv.JumpToKey("coaches", true);
    for (int i = 0; i < GetTeamCoaches(team).Length; i++) {
      GetTeamCoaches(team).GetString(i, auth, sizeof(auth));
      if (!g_PlayerNames.GetString(auth, name, sizeof(name))) {
        strcopy(name, sizeof(name), KEYVALUE_STRING_PLACEHOLDER);
      }
      kv.SetString(auth, KEYVALUE_STRING_PLACEHOLDER);
    }
    kv.GoBack();
  }
}

static bool LoadMatchFromKv(KeyValues kv) {
  kv.GetString("matchid", g_MatchID, sizeof(g_MatchID), CONFIG_MATCHID_DEFAULT);
  g_InScrimMode = kv.GetNum("scrim") != 0;
  kv.GetString("match_title", g_MatchTitle, sizeof(g_MatchTitle), CONFIG_MATCHTITLE_DEFAULT);
  g_PlayersPerTeam = kv.GetNum("players_per_team", CONFIG_PLAYERSPERTEAM_DEFAULT);
  g_SeriesCanClinch = kv.GetNum("clinch_series", CONFIG_CLINCH_SERIES_DEFAULT) != 0;
  g_CoachesPerTeam = kv.GetNum("coaches_per_team", CONFIG_COACHESPERTEAM_DEFAULT);
  g_MinPlayersToReady = kv.GetNum("min_players_to_ready", CONFIG_MINPLAYERSTOREADY_DEFAULT);
  g_MinSpectatorsToReady =
      kv.GetNum("min_spectators_to_ready", CONFIG_MINSPECTATORSTOREADY_DEFAULT);
  g_SkipVeto = kv.GetNum("skip_veto", CONFIG_SKIPVETO_DEFAULT) != 0;

  g_NumberOfMapsInSeries = kv.GetNum("num_maps", CONFIG_NUM_MAPSDEFAULT);
  g_MapsToWin = MapsToWin(g_NumberOfMapsInSeries);
  if (g_NumberOfMapsInSeries != 2 && g_NumberOfMapsInSeries % 2 == 0) {
    MatchConfigFail("Cannot create a series of %d maps. Use an odd number or 2.",
                    g_NumberOfMapsInSeries);
    return false;
  }

  char vetoFirstBuffer[64];
  kv.GetString("veto_first", vetoFirstBuffer, sizeof(vetoFirstBuffer), CONFIG_VETOFIRST_DEFAULT);
  g_LastVetoTeam = OtherMatchTeam(VetoFirstFromString(vetoFirstBuffer));

  char sideTypeBuffer[64];
  kv.GetString("side_type", sideTypeBuffer, sizeof(sideTypeBuffer), CONFIG_SIDETYPE_DEFAULT);
  g_MatchSideType = MatchSideTypeFromString(sideTypeBuffer);

  g_FavoredTeamPercentage = kv.GetNum("favored_percentage_team1", 0);
  kv.GetString("favored_percentage_text", g_FavoredTeamText, sizeof(g_FavoredTeamText));

  GetTeamPlayers(Get5Team_Spec).Clear();
  if (kv.JumpToKey("spectators")) {
    AddSubsectionAuthsToList(kv, "players", GetTeamPlayers(Get5Team_Spec));
    kv.GetString("name", g_TeamNames[Get5Team_Spec], MAX_CVAR_LENGTH,
                 CONFIG_SPECTATORSNAME_DEFAULT);
    kv.GoBack();
    FormatTeamName(Get5Team_Spec);
  }

  if (kv.JumpToKey("team1")) {
    LoadTeamData(kv, Get5Team_1);
    kv.GoBack();
  } else {
    MatchConfigFail("Missing \"team1\" section in match kv");
    return false;
  }

  if (kv.JumpToKey("team2")) {
    LoadTeamData(kv, Get5Team_2);
    kv.GoBack();
  } else {
    MatchConfigFail("Missing \"team2\" section in match kv");
    return false;
  }

  if (AddSubsectionKeysToList(kv, "maplist", g_MapPoolList, PLATFORM_MAX_PATH) <= 0) {
    LogMessage("Failed to find \"maplist\" section in config, using fallback maplist.");
    LoadDefaultMapList(g_MapPoolList);
  }

  if (g_SkipVeto) {
    if (kv.JumpToKey("map_sides")) {
      if (kv.GotoFirstSubKey(false)) {
        do {
          char buffer[64];
          kv.GetSectionName(buffer, sizeof(buffer));
          g_MapSides.Push(SideTypeFromString(buffer));
        } while (kv.GotoNextKey(false));
        kv.GoBack();
      }
      kv.GoBack();
    }
  }

  if (kv.JumpToKey("cvars")) {
    if (kv.GotoFirstSubKey(false)) {
      char name[MAX_CVAR_LENGTH];
      char value[MAX_CVAR_LENGTH];
      do {
        kv.GetSectionName(name, sizeof(name));
        ReadEmptyStringInsteadOfPlaceholder(kv, value, sizeof(value));
        g_CvarNames.PushString(name);
        g_CvarValues.PushString(value);
      } while (kv.GotoNextKey(false));
      kv.GoBack();
    }
    kv.GoBack();
  }

  return true;
}

static bool LoadMatchFromJson(JSON_Object json) {
  json_object_get_string_safe(json, "matchid", g_MatchID, sizeof(g_MatchID),
                              CONFIG_MATCHID_DEFAULT);
  g_InScrimMode = json_object_get_bool_safe(json, "scrim", false);
  g_SeriesCanClinch = json_object_get_bool_safe(json, "clinch_series", true);
  json_object_get_string_safe(json, "match_title", g_MatchTitle, sizeof(g_MatchTitle),
                              CONFIG_MATCHTITLE_DEFAULT);

  g_PlayersPerTeam =
      json_object_get_int_safe(json, "players_per_team", CONFIG_PLAYERSPERTEAM_DEFAULT);
  g_CoachesPerTeam =
      json_object_get_int_safe(json, "coaches_per_team", CONFIG_COACHESPERTEAM_DEFAULT);
  g_MinPlayersToReady =
      json_object_get_int_safe(json, "min_players_to_ready", CONFIG_MINPLAYERSTOREADY_DEFAULT);
  g_MinSpectatorsToReady = json_object_get_int_safe(json, "min_spectators_to_ready",
                                                    CONFIG_MINSPECTATORSTOREADY_DEFAULT);
  g_SkipVeto = json_object_get_bool_safe(json, "skip_veto", CONFIG_SKIPVETO_DEFAULT);

  g_NumberOfMapsInSeries = json_object_get_int_safe(json, "num_maps", CONFIG_NUM_MAPSDEFAULT);
  g_MapsToWin = MapsToWin(g_NumberOfMapsInSeries);
  if (g_NumberOfMapsInSeries != 2 && g_NumberOfMapsInSeries % 2 == 0) {
    MatchConfigFail("Cannot create a series of %d maps. Use an odd number or 2.",
                    g_NumberOfMapsInSeries);
    return false;
  }

  char vetoFirstBuffer[64];
  json_object_get_string_safe(json, "veto_first", vetoFirstBuffer, sizeof(vetoFirstBuffer),
                              CONFIG_VETOFIRST_DEFAULT);
  g_LastVetoTeam = OtherMatchTeam(VetoFirstFromString(vetoFirstBuffer));

  char sideTypeBuffer[64];
  json_object_get_string_safe(json, "side_type", sideTypeBuffer, sizeof(sideTypeBuffer),
                              CONFIG_SIDETYPE_DEFAULT);
  g_MatchSideType = MatchSideTypeFromString(sideTypeBuffer);

  json_object_get_string_safe(json, "favored_percentage_text", g_FavoredTeamText,
                              sizeof(g_FavoredTeamText));
  g_FavoredTeamPercentage = json_object_get_int_safe(json, "favored_percentage_team1", 0);

  GetTeamPlayers(Get5Team_Spec).Clear();
  JSON_Object spec = json.GetObject("spectators");
  if (spec != null) {
    json_object_get_string_safe(spec, "name", g_TeamNames[Get5Team_Spec], MAX_CVAR_LENGTH,
                                CONFIG_SPECTATORSNAME_DEFAULT);
    AddJsonAuthsToList(spec, "players", GetTeamPlayers(Get5Team_Spec), AUTH_LENGTH);
    FormatTeamName(Get5Team_Spec);
  }

  JSON_Object team1 = json.GetObject("team1");
  if (team1 != null) {
    LoadTeamDataJson(team1, Get5Team_1);
  } else {
    MatchConfigFail("Missing \"team1\" section in match json");
    return false;
  }

  JSON_Object team2 = json.GetObject("team2");
  if (team2 != null) {
    LoadTeamDataJson(team2, Get5Team_2);
  } else {
    MatchConfigFail("Missing \"team2\" section in match json");
    return false;
  }

  if (AddJsonSubsectionArrayToList(json, "maplist", g_MapPoolList, PLATFORM_MAX_PATH) <= 0) {
    LogMessage("Failed to find \"maplist\" array in match json, using fallback maplist.");
    LoadDefaultMapList(g_MapPoolList);
  }

  if (g_SkipVeto) {
    JSON_Array array = view_as<JSON_Array>(json.GetObject("map_sides"));
    if (array != null) {
      if (!array.IsArray) {
        MatchConfigFail("Expected \"map_sides\" section to be an array");
        return false;
      }
      for (int i = 0; i < array.Length; i++) {
        char buffer[64];
        array.GetString(i, buffer, sizeof(buffer));
        g_MapSides.Push(SideTypeFromString(buffer));
      }
    }
  }

  JSON_Object cvars = json.GetObject("cvars");
  if (cvars != null) {
    char cvarValue[MAX_CVAR_LENGTH];

    int length = cvars.Iterate();
    int key_length = 0;
    for (int i = 0; i < length; i++) {
      key_length = cvars.GetKeySize(i);
      char[] cvarName = new char[key_length];
      cvars.GetKey(i, cvarName, key_length);

      cvars.GetString(cvarName, cvarValue, sizeof(cvarValue));
      g_CvarNames.PushString(cvarName);
      g_CvarValues.PushString(cvarValue);
    }
  }

  return true;
}

static void LoadTeamDataJson(JSON_Object json, Get5Team matchTeam) {
  GetTeamPlayers(matchTeam).Clear();
  GetTeamCoaches(matchTeam).Clear();

  char fromfile[PLATFORM_MAX_PATH];
  json_object_get_string_safe(json, "fromfile", fromfile, sizeof(fromfile));

  if (StrEqual(fromfile, "")) {
    // TODO: this needs to support both an array and a dictionary
    // For now, it only supports an array
    AddJsonAuthsToList(json, "players", GetTeamPlayers(matchTeam), AUTH_LENGTH);
    JSON_Object coaches = json.GetObject("coaches");
    if (coaches != null) {
      AddJsonAuthsToList(json, "coaches", GetTeamCoaches(matchTeam), AUTH_LENGTH);
    }
    json_object_get_string_safe(json, "name", g_TeamNames[matchTeam], MAX_CVAR_LENGTH);
    json_object_get_string_safe(json, "tag", g_TeamTags[matchTeam], MAX_CVAR_LENGTH);
    json_object_get_string_safe(json, "flag", g_TeamFlags[matchTeam], MAX_CVAR_LENGTH);
    json_object_get_string_safe(json, "logo", g_TeamLogos[matchTeam], MAX_CVAR_LENGTH);
    json_object_get_string_safe(json, "matchtext", g_TeamMatchTexts[matchTeam], MAX_CVAR_LENGTH);
  } else {
    JSON_Object fromfileJson = json_read_from_file(fromfile);
    if (fromfileJson == null) {
      LogError("Cannot load team config from file \"%s\", fromfile");
    } else {
      LoadTeamDataJson(fromfileJson, matchTeam);
      json_cleanup_and_delete(fromfileJson);
    }
  }

  g_TeamSeriesScores[matchTeam] = json_object_get_int_safe(json, "series_score", 0);
  FormatTeamName(matchTeam);
}

static void LoadTeamData(KeyValues kv, Get5Team matchTeam) {
  GetTeamPlayers(matchTeam).Clear();
  GetTeamCoaches(matchTeam).Clear();
  char fromfile[PLATFORM_MAX_PATH];
  kv.GetString("fromfile", fromfile, sizeof(fromfile));

  if (StrEqual(fromfile, "")) {
    AddSubsectionAuthsToList(kv, "players", GetTeamPlayers(matchTeam));
    AddSubsectionAuthsToList(kv, "coaches", GetTeamCoaches(matchTeam));
    kv.GetString("name", g_TeamNames[matchTeam], MAX_CVAR_LENGTH, "");
    kv.GetString("tag", g_TeamTags[matchTeam], MAX_CVAR_LENGTH, "");
    kv.GetString("flag", g_TeamFlags[matchTeam], MAX_CVAR_LENGTH, "");
    kv.GetString("logo", g_TeamLogos[matchTeam], MAX_CVAR_LENGTH, "");
    kv.GetString("matchtext", g_TeamMatchTexts[matchTeam], MAX_CVAR_LENGTH, "");
  } else {
    KeyValues fromfilekv = new KeyValues("team");
    if (fromfilekv.ImportFromFile(fromfile)) {
      LoadTeamData(fromfilekv, matchTeam);
    } else {
      LogError("Cannot load team config from file \"%s\"", fromfile);
    }
    delete fromfilekv;
  }

  g_TeamSeriesScores[matchTeam] = kv.GetNum("series_score", 0);
  FormatTeamName(matchTeam);
}

static void FormatTeamName(const Get5Team team) {
  char color[32];
  char teamNameFallback[MAX_CVAR_LENGTH];
  if (team == Get5Team_1) {
    g_Team1NameColorCvar.GetString(color, sizeof(color));
    teamNameFallback = "team1";
  } else if (team == Get5Team_2) {
    g_Team2NameColorCvar.GetString(color, sizeof(color));
    teamNameFallback = "team2";
  } else if (team == Get5Team_Spec) {
    g_SpecNameColorCvar.GetString(color, sizeof(color));
  } else {
    color = "{NORMAL}";
  }
  Format(g_FormattedTeamNames[team], MAX_CVAR_LENGTH, "%s%s{NORMAL}", color,
         strlen(g_TeamNames[team]) > 0 ? g_TeamNames[team] : teamNameFallback);
}

static void LoadDefaultMapList(ArrayList list) {
  list.PushString("de_ancient");
  list.PushString("de_dust2");
  list.PushString("de_inferno");
  list.PushString("de_mirage");
  list.PushString("de_nuke");
  list.PushString("de_overpass");
  list.PushString("de_vertigo");

  if (g_SkipVeto) {
    char currentMap[PLATFORM_MAX_PATH];
    GetCurrentMap(currentMap, sizeof(currentMap));

    int currentMapIndex = list.FindString(currentMap);
    if (currentMapIndex > 0) {
      list.SwapAt(0, currentMapIndex);
    }
  }
}

void SetMatchTeamCvars() {
  Get5Team ctTeam = Get5Team_1;
  Get5Team tTeam = Get5Team_2;
  if (g_TeamStartingSide[Get5Team_1] == CS_TEAM_T) {
    ctTeam = Get5Team_2;
    tTeam = Get5Team_1;
  }

  // Get the match configs set by the config file.
  // These might be modified so copies are made here.
  char ctMatchText[MAX_CVAR_LENGTH];
  char tMatchText[MAX_CVAR_LENGTH];
  strcopy(ctMatchText, sizeof(ctMatchText), g_TeamMatchTexts[ctTeam]);
  strcopy(tMatchText, sizeof(tMatchText), g_TeamMatchTexts[tTeam]);

  // Update mp_teammatchstat_txt with the match title.
  char mapstat[MAX_CVAR_LENGTH];
  strcopy(mapstat, sizeof(mapstat), g_MatchTitle);
  ReplaceStringWithInt(mapstat, sizeof(mapstat), "{MAPNUMBER}", Get5_GetMapNumber() + 1, false);
  ReplaceStringWithInt(mapstat, sizeof(mapstat), "{MAXMAPS}", g_NumberOfMapsInSeries, false);
  SetConVarStringSafe("mp_teammatchstat_txt", mapstat);

  if (g_MapsToWin >= 3) {
    char team1Text[MAX_CVAR_LENGTH];
    char team2Text[MAX_CVAR_LENGTH];
    IntToString(g_TeamSeriesScores[Get5Team_1], team1Text, sizeof(team1Text));
    IntToString(g_TeamSeriesScores[Get5Team_2], team2Text, sizeof(team2Text));

    MatchTeamStringsToCSTeam(team1Text, team2Text, ctMatchText, sizeof(ctMatchText), tMatchText,
                             sizeof(tMatchText));
  }

  SetTeamInfo(CS_TEAM_CT, g_TeamNames[ctTeam], g_TeamFlags[ctTeam], g_TeamLogos[ctTeam],
              ctMatchText, g_TeamSeriesScores[ctTeam]);

  SetTeamInfo(CS_TEAM_T, g_TeamNames[tTeam], g_TeamFlags[tTeam], g_TeamLogos[tTeam], tMatchText,
              g_TeamSeriesScores[tTeam]);

  // Set prediction cvars.
  SetConVarStringSafe("mp_teamprediction_txt", g_FavoredTeamText);
  if (g_TeamSide[Get5Team_1] == CS_TEAM_CT) {
    SetConVarIntSafe("mp_teamprediction_pct", g_FavoredTeamPercentage);
  } else {
    SetConVarIntSafe("mp_teamprediction_pct", 100 - g_FavoredTeamPercentage);
  }

  if (g_MapsToWin > 1) {
    SetConVarIntSafe("mp_teamscore_max", g_MapsToWin);
  }

  char formattedHostname[128];

  if (FormatCvarString(g_SetHostnameCvar, formattedHostname, sizeof(formattedHostname))) {
    SetConVarStringSafe("hostname", formattedHostname);
  }
}

static void ExecuteMatchConfigCvars() {
  // Save the original match cvar values if we haven't already.
  if (g_MatchConfigChangedCvars == INVALID_HANDLE) {
    g_MatchConfigChangedCvars = SaveCvars(g_CvarNames);
  }

  char name[MAX_CVAR_LENGTH];
  char value[MAX_CVAR_LENGTH];
  for (int i = 0; i < g_CvarNames.Length; i++) {
    g_CvarNames.GetString(i, name, sizeof(name));
    g_CvarValues.GetString(i, value, sizeof(value));
    ConVar cvar = FindConVar(name);
    if (cvar == null) {
      ServerCommand("%s %s", name, value);
    } else {
      cvar.SetString(value);
    }
  }
}

Action Command_LoadTeam(int client, int args) {
  if (g_GameState == Get5State_None) {
    ReplyToCommand(client, "Cannot change player lists when there is no match to modify");
    return Plugin_Handled;
  }

  char arg1[PLATFORM_MAX_PATH];
  char arg2[PLATFORM_MAX_PATH];
  if (args >= 2 && GetCmdArg(1, arg1, sizeof(arg1)) && GetCmdArg(2, arg2, sizeof(arg2))) {
    Get5Team team = Get5Team_None;
    if (StrEqual(arg1, "team1")) {
      team = Get5Team_1;
    } else if (StrEqual(arg1, "team2")) {
      team = Get5Team_2;
    } else if (StrEqual(arg1, "spec")) {
      team = Get5Team_Spec;
    } else {
      ReplyToCommand(client, "Unknown team: must be one of team1, team2, spec");
      return Plugin_Handled;
    }

    KeyValues kv = new KeyValues("team");
    if (kv.ImportFromFile(arg2)) {
      LoadTeamData(kv, team);
      ReplyToCommand(client, "Loaded team data for %s", arg1);
      SetMatchTeamCvars();
    } else {
      ReplyToCommand(client, "Failed to read keyvalues from file \"%s\"", arg2);
    }
    delete kv;

  } else {
    ReplyToCommand(client, "Usage: get_loadteam <team1|team2|spec> <filename>");
  }

  return Plugin_Handled;
}

Action Command_AddPlayer(int client, int args) {
  if (g_GameState == Get5State_None) {
    ReplyToCommand(client, "No match configuration was loaded.");
    return Plugin_Handled;
  } else if (g_InScrimMode) {
    ReplyToCommand(
        client,
        "Cannot use get5_addplayer in scrim mode. Use get5_ringer to swap a player's team.");
    return Plugin_Handled;
  } else if (g_DoingBackupRestoreNow || g_WaitingForRoundBackup) {
    ReplyToCommand(client, "Cannot add players while waiting for round backup.");
    return Plugin_Handled;
  } else if (g_PendingSideSwap || InHalftimePhase()) {
    ReplyToCommand(client,
                   "Cannot add players during halftime. Please wait until the next round starts.");
    return Plugin_Handled;
  }

  char auth[AUTH_LENGTH];
  char teamString[32];
  char name[MAX_NAME_LENGTH];
  if (args >= 2 && GetCmdArg(1, auth, sizeof(auth)) &&
      GetCmdArg(2, teamString, sizeof(teamString))) {
    if (args >= 3) {
      GetCmdArg(3, name, sizeof(name));
    }

    Get5Team team = Get5Team_None;
    if (StrEqual(teamString, "team1")) {
      team = Get5Team_1;
    } else if (StrEqual(teamString, "team2")) {
      team = Get5Team_2;
    } else if (StrEqual(teamString, "spec")) {
      team = Get5Team_Spec;
    } else {
      ReplyToCommand(client, "Unknown team: must be one of team1, team2, spec");
      return Plugin_Handled;
    }

    if (AddPlayerToTeam(auth, team, name)) {
      ReplyToCommand(client, "Successfully added player %s to %s.", auth, teamString);
    } else {
      ReplyToCommand(
          client,
          "Failed to add player %s to team %. They may already be on a team or you provided an invalid Steam ID.",
          auth, teamString);
    }

  } else {
    ReplyToCommand(client, "Usage: get5_addplayer <auth> <team1|team2|spec> [name]");
  }
  return Plugin_Handled;
}

Action Command_AddCoach(int client, int args) {
  if (g_GameState == Get5State_None) {
    ReplyToCommand(client, "No match configuration was loaded.");
    return Plugin_Handled;
  } else if (!g_CoachingEnabledCvar.BoolValue) {
    ReplyToCommand(client, "Coaching is not enabled.");
    return Plugin_Handled;
  } else if (g_InScrimMode) {
    ReplyToCommand(client,
                   "Coaches cannot be added in scrim mode. Use the !coach command in chat.");
    return Plugin_Handled;
  } else if (g_DoingBackupRestoreNow || g_WaitingForRoundBackup) {
    ReplyToCommand(client, "Cannot add coaches while waiting for round backup.");
    return Plugin_Handled;
  } else if (g_PendingSideSwap || InHalftimePhase()) {
    ReplyToCommand(client,
                   "Cannot add coaches during halftime. Please wait until the next round starts.");
    return Plugin_Handled;
  }

  char auth[AUTH_LENGTH];
  char teamString[32];
  char name[MAX_NAME_LENGTH];
  if (args >= 2 && GetCmdArg(1, auth, sizeof(auth)) &&
      GetCmdArg(2, teamString, sizeof(teamString))) {
    if (args >= 3) {
      GetCmdArg(3, name, sizeof(name));
    }

    Get5Team team = Get5Team_None;
    if (StrEqual(teamString, "team1")) {
      team = Get5Team_1;
    } else if (StrEqual(teamString, "team2")) {
      team = Get5Team_2;
    } else {
      ReplyToCommand(client, "Unknown team: must be one of team1 or team2");
      return Plugin_Handled;
    }

    if (CountCoachesOnTeam(team) == g_CoachesPerTeam) {
      ReplyToCommand(client, "Coach Spots are full for %s.", teamString);
      return Plugin_Handled;
    }

    if (AddCoachToTeam(auth, team, name)) {
      // If the player is already on the team as a regular player, remove them when adding to
      // coaches.
      int index = GetTeamPlayers(team).FindString(auth);
      if (index >= 0) {
        GetTeamPlayers(team).Erase(index);
      }

      ReplyToCommand(client, "Successfully added player %s as coach for %s.", auth, teamString);

      // If the user is already on the server as a player, move them to coaching immediately.
      int addedClient = AuthToClient(auth);
      if (addedClient > 0 && IsClientConnected(addedClient)) {
        Get5Side side = view_as<Get5Side>(Get5TeamToCSTeam(team));
        if (side != Get5Side_None) {
          LogDebug(
              "Player %s was present on the server when added as coach; moving them to coach for %d.",
              auth, team);
          SetClientCoaching(addedClient, side);
        }
      }
    } else {
      ReplyToCommand(
          client,
          "Failed to add player %s as coach for %s. They may already be coaching or you provided an invalid Steam ID.",
          auth, teamString);
    }
  } else {
    ReplyToCommand(client, "Usage: get5_addcoach <auth> <team1|team2> [name]");
  }
  return Plugin_Handled;
}

Action Command_AddKickedPlayer(int client, int args) {
  if (g_GameState == Get5State_None) {
    ReplyToCommand(client, "No match configuration was loaded.");
    return Plugin_Handled;
  } else if (g_InScrimMode) {
    ReplyToCommand(
        client,
        "Cannot use get5_addkickedplayer in scrim mode. Use get5_ringer to swap a player's team.");
    return Plugin_Handled;
  } else if (g_DoingBackupRestoreNow || g_WaitingForRoundBackup) {
    ReplyToCommand(client, "Cannot add players while waiting for round backup.");
    return Plugin_Handled;
  } else if (g_PendingSideSwap || InHalftimePhase()) {
    ReplyToCommand(client,
                   "Cannot add players during halftime. Please wait until the next round starts.");
    return Plugin_Handled;
  }

  if (StrEqual(g_LastKickedPlayerAuth, "")) {
    ReplyToCommand(client, "No player has been kicked yet.");
    return Plugin_Handled;
  }

  char teamString[32];
  char name[MAX_NAME_LENGTH];
  if (args >= 1 && GetCmdArg(1, teamString, sizeof(teamString))) {
    if (args >= 2) {
      GetCmdArg(2, name, sizeof(name));
    }

    Get5Team team = Get5Team_None;
    if (StrEqual(teamString, "team1")) {
      team = Get5Team_1;
    } else if (StrEqual(teamString, "team2")) {
      team = Get5Team_2;
    } else if (StrEqual(teamString, "spec")) {
      team = Get5Team_Spec;
    } else {
      ReplyToCommand(client, "Unknown team: must be one of team1, team2, spec");
      return Plugin_Handled;
    }

    if (AddPlayerToTeam(g_LastKickedPlayerAuth, team, name)) {
      ReplyToCommand(client, "Successfully added kicked player %s to %s.", g_LastKickedPlayerAuth,
                     teamString);
    } else {
      ReplyToCommand(
          client,
          "Failed to add player %s to %s. They may already be on a team or you provided an invalid Steam ID.",
          g_LastKickedPlayerAuth, teamString);
    }

  } else {
    ReplyToCommand(client, "Usage: get5_addkickedplayer <team1|team2|spec> [name]");
  }
  return Plugin_Handled;
}

Action Command_RemovePlayer(int client, int args) {
  if (g_GameState == Get5State_None) {
    ReplyToCommand(client, "Cannot change player lists when there is no match to modify");
    return Plugin_Handled;
  }

  if (g_InScrimMode) {
    ReplyToCommand(
        client,
        "Cannot use get5_removeplayer in scrim mode. Use get5_ringer to swap a player's team.");
    return Plugin_Handled;
  }

  char auth[AUTH_LENGTH];
  if (args >= 1 && GetCmdArg(1, auth, sizeof(auth))) {
    if (RemovePlayerFromTeams(auth)) {
      ReplyToCommand(client, "Successfully removed player %s.", auth);
    } else {
      ReplyToCommand(client, "Player %s not found in auth lists or the Steam ID was invalid.",
                     auth);
    }
  } else {
    ReplyToCommand(client, "Usage: get5_removeplayer <auth>");
  }
  return Plugin_Handled;
}

Action Command_RemoveKickedPlayer(int client, int args) {
  if (g_GameState == Get5State_None) {
    ReplyToCommand(client, "Cannot change player lists when there is no match to modify.");
    return Plugin_Handled;
  }

  if (g_InScrimMode) {
    ReplyToCommand(
        client,
        "Cannot use get5_removekickedplayer in scrim mode. Use get5_ringer to swap a players team.");
    return Plugin_Handled;
  }

  if (StrEqual(g_LastKickedPlayerAuth, "")) {
    ReplyToCommand(client, "No player has been kicked yet.");
    return Plugin_Handled;
  }

  if (RemovePlayerFromTeams(g_LastKickedPlayerAuth)) {
    ReplyToCommand(client, "Successfully removed kicked player %s.", g_LastKickedPlayerAuth);
  } else {
    ReplyToCommand(client, "Player %s not found in auth lists or the Steam ID was invalid.",
                   g_LastKickedPlayerAuth);
  }
  return Plugin_Handled;
}

Action Command_CreateMatch(int client, int args) {
  if (g_GameState != Get5State_None) {
    ReplyToCommand(client, "Cannot create a match when a match is already loaded");
    return Plugin_Handled;
  }

  char matchid[MATCH_ID_LENGTH] = "manual";
  char matchMap[PLATFORM_MAX_PATH];
  GetCleanMapName(matchMap, sizeof(matchMap));

  if (args >= 1) {
    GetCmdArg(1, matchMap, sizeof(matchMap));
    if (!IsMapValid(matchMap)) {
      ReplyToCommand(client, "Invalid map: %s", matchMap);
      return Plugin_Handled;
    }
  }
  if (args >= 2) {
    GetCmdArg(2, matchid, sizeof(matchid));
  }

  char path[PLATFORM_MAX_PATH];
  Format(path, sizeof(path), "get5_%s.cfg", matchid);
  DeleteFileIfExists(path);

  KeyValues kv = new KeyValues("Match");
  kv.SetString("matchid", matchid);
  kv.SetNum("num_maps", 1);
  kv.SetNum("skip_veto", 1);
  kv.SetNum("players_per_team", 5);
  kv.SetNum("clinch_series", 1);

  kv.JumpToKey("maplist", true);
  kv.SetString(matchMap, KEYVALUE_STRING_PLACEHOLDER);
  kv.GoBack();

  char teamName[MAX_CVAR_LENGTH];

  // If team names are empty because nobody is on on the server, the will be set by
  // CheckTeamNameStatus during ready-phase. We cannot write empty strings to KeyValues, so we just
  // skip them.
  kv.JumpToKey("team1", true);
  if (AddPlayersToAuthKv(kv, Get5Team_1, teamName) > 0) {
    kv.SetString("name", teamName);
  }
  kv.GoBack();

  kv.JumpToKey("team2", true);
  if (AddPlayersToAuthKv(kv, Get5Team_2, teamName) > 0) {
    kv.SetString("name", teamName);
  }
  kv.GoBack();

  kv.JumpToKey("spectators", true);
  AddPlayersToAuthKv(kv, Get5Team_Spec, teamName);
  kv.GoBack();

  if (!kv.ExportToFile(path)) {
    delete kv;
    MatchConfigFail("Failed to read write match config to %s", path);
    return Plugin_Handled;
  }

  delete kv;
  LoadMatchConfig(path);
  return Plugin_Handled;
}

Action Command_CreateScrim(int client, int args) {
  if (g_GameState != Get5State_None) {
    ReplyToCommand(client, "Cannot create a match when a match is already loaded");
    return Plugin_Handled;
  }

  char matchid[MATCH_ID_LENGTH] = "scrim";
  char matchMap[PLATFORM_MAX_PATH];
  GetCleanMapName(matchMap, sizeof(matchMap));
  char otherTeamName[MAX_CVAR_LENGTH] = "Away";

  if (args >= 1) {
    GetCmdArg(1, otherTeamName, sizeof(otherTeamName));
  }
  if (args >= 2) {
    GetCmdArg(2, matchMap, sizeof(matchMap));
    if (!IsMapValid(matchMap)) {
      ReplyToCommand(client, "Invalid map: %s", matchMap);
      return Plugin_Handled;
    }
  }
  if (args >= 3) {
    GetCmdArg(3, matchid, sizeof(matchid));
  }

  char path[PLATFORM_MAX_PATH];
  Format(path, sizeof(path), "get5_%s.cfg", matchid);
  DeleteFileIfExists(path);

  KeyValues kv = new KeyValues("Match");
  kv.SetString("matchid", matchid);
  kv.SetNum("scrim", 1);
  kv.JumpToKey("maplist", true);
  kv.SetString(matchMap, KEYVALUE_STRING_PLACEHOLDER);
  kv.GoBack();

  char templateFile[PLATFORM_MAX_PATH + 1];
  BuildPath(Path_SM, templateFile, sizeof(templateFile), "configs/get5/scrim_template.cfg");
  if (!kv.ImportFromFile(templateFile)) {
    delete kv;
    MatchConfigFail("Failed to read scrim template in %s", templateFile);
    return Plugin_Handled;
  }
  // Because we read the field and write it again, then load it as a match config, we have to make
  // sure empty strings are not being skipped.
  if (kv.JumpToKey("team1") && kv.JumpToKey("players") && kv.GotoFirstSubKey(false)) {
    char name[MAX_NAME_LENGTH];
    do {
      WritePlaceholderInsteadOfEmptyString(kv, name, sizeof(name));
    } while (kv.GotoNextKey(false));
    kv.Rewind();
  } else {
    delete kv;
    MatchConfigFail("You must add players to team1 on your scrim template!");
    return Plugin_Handled;
  }

  // Allow spectators in scrim template.
  if (kv.JumpToKey("spectators") && kv.JumpToKey("players") && kv.GotoFirstSubKey(false)) {
    char name[MAX_NAME_LENGTH];
    do {
      WritePlaceholderInsteadOfEmptyString(kv, name, sizeof(name));
    } while (kv.GotoNextKey(false));
    kv.Rewind();
  }

  // Also ensure empty string values in cvars get printed to the match config.
  if (kv.JumpToKey("cvars")) {
    if (kv.GotoFirstSubKey(false)) {
      char cVarValue[MAX_CVAR_LENGTH];
      do {
        WritePlaceholderInsteadOfEmptyString(kv, cVarValue, sizeof(cVarValue));
      } while (kv.GotoNextKey(false));
      kv.GoBack();
    }
    kv.GoBack();
  }

  kv.JumpToKey("team2", true);
  kv.SetString("name", otherTeamName);
  kv.GoBack();

  if (!kv.ExportToFile(path)) {
    delete kv;
    MatchConfigFail("Failed to read write scrim config to %s", path);
    return Plugin_Handled;
  }

  delete kv;
  LoadMatchConfig(path);
  return Plugin_Handled;
}

Action Command_Ringer(int client, int args) {
  if (g_GameState == Get5State_None || !g_InScrimMode) {
    ReplyToCommand(client, "This command can only be used in scrim mode.");
    return Plugin_Handled;
  }

  char arg1[32];
  if (args >= 1 && GetCmdArg(1, arg1, sizeof(arg1))) {
    int target = FindTarget(client, arg1, true, false);
    if (IsAuthedPlayer(target)) {
      SwapScrimTeamStatus(target);
    } else {
      ReplyToCommand(client, "Player not found");
    }
  } else {
    ReplyToCommand(client, "Usage: sm_ringer <player>");
  }

  return Plugin_Handled;
}

static int AddPlayersToAuthKv(KeyValues kv, Get5Team team, char teamName[MAX_CVAR_LENGTH]) {
  int count = 0;
  kv.JumpToKey("players", true);
  bool gotClientName = false;
  char auth[AUTH_LENGTH];
  LOOP_CLIENTS(i) {
    if (IsAuthedPlayer(i)) {
      int csTeam = GetClientTeam(i);
      Get5Team t = Get5Team_None;
      if (csTeam == TEAM1_STARTING_SIDE) {
        t = Get5Team_1;
      } else if (csTeam == TEAM2_STARTING_SIDE) {
        t = Get5Team_2;
      } else if (csTeam == CS_TEAM_SPECTATOR) {
        t = Get5Team_Spec;
      }

      if (t == team) {
        if (!gotClientName) {
          gotClientName = true;
          char clientName[MAX_NAME_LENGTH];
          GetClientName(i, clientName, sizeof(clientName));
          Format(teamName, sizeof(teamName), "team_%s", clientName);
        }

        count++;
        if (GetAuth(i, auth, sizeof(auth))) {
          kv.SetString(auth, KEYVALUE_STRING_PLACEHOLDER);
        }
      }
    }
  }
  kv.GoBack();
  return count;
}

static void MatchTeamStringsToCSTeam(const char[] team1Str, const char[] team2Str, char[] ctStr,
                                     int ctLen, char[] tStr, int tLen) {
  if (Get5TeamToCSTeam(Get5Team_1) == CS_TEAM_CT) {
    strcopy(ctStr, ctLen, team1Str);
    strcopy(tStr, tLen, team2Str);
  } else {
    strcopy(tStr, tLen, team1Str);
    strcopy(ctStr, ctLen, team2Str);
  }
}

// Adds the team logos to the download table.
static void AddTeamLogosToDownloadTable() {
  AddTeamLogoToDownloadTable(g_TeamLogos[Get5Team_1]);
  AddTeamLogoToDownloadTable(g_TeamLogos[Get5Team_2]);
}

static void AddTeamLogoToDownloadTable(const char[] logoName) {
  if (StrEqual(logoName, ""))
    return;

  char logoPath[PLATFORM_MAX_PATH + 1];
  Format(logoPath, sizeof(logoPath), "materials/panorama/images/tournaments/teams/%s.svg",
         logoName);
  if (FileExists(logoPath)) {
    LogDebug("Adding file %s to download table", logoName);
    AddFileToDownloadsTable(logoPath);
  } else {
    Format(logoPath, sizeof(logoPath), "resource/flash/econ/tournaments/teams/%s.png", logoName);
    if (FileExists(logoPath)) {
      LogDebug("Adding file %s to download table", logoName);
      AddFileToDownloadsTable(logoPath);
    } else {
      LogError("Error in locating file %s. Please ensure the file exists on your game server.",
               logoPath);
    }
  }
}

void CheckTeamNameStatus(Get5Team team) {
  if (StrEqual(g_TeamNames[team], "") && team != Get5Team_Spec) {
    LOOP_CLIENTS(i) {
      if (IsAuthedPlayer(i)) {
        if (GetClientMatchTeam(i) == team) {
          char clientName[MAX_NAME_LENGTH];
          GetClientName(i, clientName, sizeof(clientName));
          Format(g_TeamNames[team], MAX_CVAR_LENGTH, "team_%s", clientName);
          break;
        }
      }
    }
    FormatTeamName(team);
  }
}

void ExecCfg(ConVar cvar) {
  char cfg[PLATFORM_MAX_PATH];
  cvar.GetString(cfg, sizeof(cfg));
  ServerCommand("exec \"%s\"", cfg);
  CreateTimer(0.1, Timer_ExecMatchConfig, _, TIMER_FLAG_NO_MAPCHANGE);
}

static Action Timer_ExecMatchConfig(Handle timer) {
  // When we load config files using ServerCommand("exec") above, which is async, we want match
  // config cvars to always override.
  ExecuteMatchConfigCvars();
  SetMatchTeamCvars();
  return Plugin_Handled;
}
