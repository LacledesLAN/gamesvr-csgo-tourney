// TODO: Add translations for this.
// TODO: Add admin top menu integration.

Action Command_Get5AdminMenu(int client, int args) {
  Menu menu = new Menu(AdminMenuHandler);
  menu.SetTitle("Get5 Admin Menu");

  // Add actual choices
  menu.AddItem("get5_scrim", "Create a scrim", EnabledIf(g_GameState == Get5State_None));
  menu.AddItem("get5_creatematch", "Create match with current players",
               EnabledIf(g_GameState == Get5State_None));
  menu.AddItem("get5_forceready", "Force-ready all players",
               EnabledIf(g_GameState == Get5State_Warmup || g_GameState == Get5State_PreVeto));
  menu.AddItem("get5_endmatch", "End match", EnabledIf(g_GameState != Get5State_None));
  menu.AddItem("ringer", "Add scrim ringer",
               EnabledIf(g_InScrimMode && g_GameState != Get5State_None));
  menu.AddItem("sm_swap", "Swap scrim sides",
               EnabledIf(g_InScrimMode && g_GameState == Get5State_Warmup));

  char lastBackup[PLATFORM_MAX_PATH];
  g_LastGet5BackupCvar.GetString(lastBackup, sizeof(lastBackup));
  menu.AddItem("backup", "Load last backup file",
               EnabledIf(g_GameState != Get5State_None && !StrEqual(lastBackup, "")));

  menu.Pagination = MENU_NO_PAGINATION;
  menu.ExitButton = true;

  menu.Display(client, MENU_TIME_FOREVER);
  return Plugin_Handled;
}

static int EnabledIf(bool cond) {
  return cond ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED;
}

static int AdminMenuHandler(Menu menu, MenuAction action, int param1, int param2) {
  if (action == MenuAction_Select) {
    int client = param1;
    char infoString[64];
    menu.GetItem(param2, infoString, sizeof(infoString));
    if (StrEqual(infoString, "get5_scrim") || StrEqual(infoString, "get5_creatematch") ||
        StrEqual(infoString, "get5_forceready") || StrEqual(infoString, "get5_endmatch") ||
        StrEqual(infoString, "sm_swap")) {
      FakeClientCommand(client, infoString);
    } else if (StrEqual(infoString, "ringer")) {
      GiveRingerMenu(client);
    } else if (StrEqual(infoString, "backup")) {
      RestoreLastRound(client);
    }
  } else if (action == MenuAction_End) {
    delete menu;
  }
}

static void GiveRingerMenu(int client) {
  Menu menu = new Menu(RingerMenuHandler);
  menu.SetTitle("Switch scrim team status");
  menu.ExitButton = true;
  menu.ExitBackButton = true;

  LOOP_CLIENTS(i) {
    if (IsPlayer(i)) {
      char infoString[64];
      IntToString(GetClientSerial(i), infoString, sizeof(infoString));
      char displayString[64];
      Format(displayString, sizeof(displayString), "%N", i);
      menu.AddItem(infoString, displayString);
    }
  }
  menu.Display(client, MENU_TIME_FOREVER);
}

static int RingerMenuHandler(Menu menu, MenuAction action, int param1, int param2) {
  if (action == MenuAction_Select) {
    int client = param1;
    char infoString[64];
    menu.GetItem(param2, infoString, sizeof(infoString));
    int choiceSerial = StringToInt(infoString);
    int choiceClient = GetClientFromSerial(choiceSerial);
    if (IsPlayer(choiceClient)) {
      SwapScrimTeamStatus(choiceClient);
      Get5_Message(client, "Swapped scrim team status for %N.", choiceClient);
    }
  } else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack) {
    int client = param1;
    Command_Get5AdminMenu(client, 0);
  } else if (action == MenuAction_End) {
    delete menu;
  }
}
