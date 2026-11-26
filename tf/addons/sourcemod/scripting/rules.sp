#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

// ---------------------------------------------------------------------
// Rules - shows the server rules when a player types !rules or /rules
// in chat (or runs sm_rules in console). Rules that have a longer
// explanation get an "Explain rule N" button.
//
// Rules are read from: addons/sourcemod/configs/rules_required/rules.txt
//
// File format, one rule per line:
//     Rule text | Longer explanation shown when its button is pressed
// The explanation is optional. Use \n inside an explanation for a new paragraph.
//
// TF2's menu does not wrap long lines (they run off the screen), so this
// plugin word-wraps all text itself.
// ---------------------------------------------------------------------

#define PLUGIN_VERSION          "1.0.0"
#define RULES_CONFIG_FILE       "configs/rules/rules.txt"
#define MAX_RULE_LINES          256
#define MAX_LINE_LEN            192     // max length of a rule's text
#define MAX_EXPLAIN_LEN         1024    // max length of one rule's explanation

#define WRAP_WIDTH              56      // characters per line; lower it if lines still run off screen
#define DETAIL_LINES_PER_PAGE   7       // explanation lines per page; lower it if text gets cut off
#define MAX_WRAP_LINES          64
#define WRAP_LINE_SIZE          96

#define DIVIDER                 "------------------------------------------------"

#define MENUITEM_NEXT   "__next"
#define MENUITEM_PREV   "__prev"
#define MENUITEM_BACK   "__back"
#define MENUITEM_CLOSE  "__close"

ConVar g_cvLinesPerPage;

int  g_iCurrentPage[MAXPLAYERS + 1];
int  g_iDetailRule[MAXPLAYERS + 1];
int  g_iDetailPage[MAXPLAYERS + 1];

char g_sRuleLines[MAX_RULE_LINES][MAX_LINE_LEN];
char g_sRuleExplain[MAX_RULE_LINES][MAX_EXPLAIN_LEN];
int  g_iRuleLineCount;

public Plugin myinfo =
{
    name        = "Rules",
    author      = "Senni",
    description = "Shows the server rules (with per-rule explanations) when a player types !rules or /rules",
    version     = PLUGIN_VERSION,
    url         = ""
};

// ---------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------

public void OnPluginStart()
{
    g_cvLinesPerPage = CreateConVar("sm_rules_lines_per_page", "4", "How many rules to show per menu page.", _, true, 1.0, true, 5.0);

    AutoExecConfig(true, "rules_required");

    // sm_rules is also what makes !rules and /rules work in chat
    // (SourceMod maps the ! and / chat triggers to sm_ commands).
    RegConsoleCmd("sm_rules", Cmd_Rules, "Shows the server rules.");
    RegAdminCmd("sm_reloadrules", Cmd_ReloadRules, ADMFLAG_KICK, "sm_reloadrules - reloads rules.txt from disk.");

    LoadRulesFile();
}

public void OnConfigsExecuted()
{
    // Rules file may have been edited; keep it reloadable without a full plugin reload.
    LoadRulesFile();
}

public void OnClientPutInServer(int client)
{
    g_iCurrentPage[client] = 0;
    g_iDetailRule[client]  = -1;
    g_iDetailPage[client]  = 0;
}

public void OnClientDisconnect(int client)
{
    g_iCurrentPage[client] = 0;
    g_iDetailRule[client]  = -1;
    g_iDetailPage[client]  = 0;
}

// ---------------------------------------------------------------------
// Rules file loading
// ---------------------------------------------------------------------

void LoadRulesFile()
{
    g_iRuleLineCount = 0;

    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath), RULES_CONFIG_FILE);

    if (!FileExists(sPath))
    {
        CreateDefaultRulesFile(sPath);
    }

    File hFile = OpenFile(sPath, "r");
    if (hFile == null)
    {
        LogError("[Rules] Could not open rules file at %s", sPath);
        return;
    }

    char sLine[MAX_LINE_LEN + MAX_EXPLAIN_LEN + 8];
    char sExplain[MAX_EXPLAIN_LEN];

    while (!hFile.EndOfFile() && hFile.ReadLine(sLine, sizeof(sLine)))
    {
        TrimString(sLine);

        // Skip blank lines and comment lines.
        if (sLine[0] == '\0' || (sLine[0] == '/' && sLine[1] == '/') || sLine[0] == ';')
        {
            continue;
        }

        if (g_iRuleLineCount >= MAX_RULE_LINES)
        {
            LogError("[Rules] rules.txt has more than %d lines, extra lines ignored.", MAX_RULE_LINES);
            break;
        }

        // Split "rule text | explanation" at the first '|'.
        sExplain[0] = '\0';
        int iSplit = FindCharInString(sLine, '|');
        if (iSplit != -1)
        {
            strcopy(sExplain, sizeof(sExplain), sLine[iSplit + 1]);
            sLine[iSplit] = '\0';
            TrimString(sExplain);
            ReplaceString(sExplain, sizeof(sExplain), "\\n", "\n");
        }

        TrimString(sLine);
        if (sLine[0] == '\0')
        {
            continue;
        }

        strcopy(g_sRuleLines[g_iRuleLineCount], MAX_LINE_LEN, sLine);
        strcopy(g_sRuleExplain[g_iRuleLineCount], MAX_EXPLAIN_LEN, sExplain);
        g_iRuleLineCount++;
    }

    delete hFile;

    if (g_iRuleLineCount == 0)
    {
        strcopy(g_sRuleLines[0], MAX_LINE_LEN, "The server admin has not configured any rules yet.");
        g_sRuleExplain[0][0] = '\0';
        g_iRuleLineCount = 1;
    }
}

void CreateDefaultRulesFile(const char[] sPath)
{
    File hFile = OpenFile(sPath, "w");
    if (hFile == null)
    {
        LogError("[Rules] Could not create default rules file at %s", sPath);
        return;
    }

    hFile.WriteLine("// One rule per line. Blank lines and lines starting with // or ; are ignored.");
    hFile.WriteLine("// Edit this file, then change map or run: sm_reloadrules");
    hFile.WriteLine("//");
    hFile.WriteLine("// Format:  Rule text | Longer explanation (optional)");
    hFile.WriteLine("// Rules with an explanation get an \"Explain rule N\" button.");
    hFile.WriteLine("// Use \\n inside an explanation for a new paragraph.");
    hFile.WriteLine("// Long lines are word-wrapped automatically.");
    hFile.WriteLine("1. Be respectful to players and staff. | Disrespectful or derogatory behavior is not tolerated.");
    hFile.WriteLine("2. No cheating or exploiting bugs. | Cheating results in a ban, and most cases are not appealable.");
    hFile.WriteLine("3. Don't spam chat, mic, or sprays.");
    hFile.WriteLine("4. Follow admin/moderator instructions.");

    delete hFile;
}

// ---------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------

public Action Cmd_Rules(int client, int args)
{
    if (client <= 0)
    {
        return Plugin_Handled;
    }
    ShowRulesMenu(client, 0);
    return Plugin_Handled;
}

public Action Cmd_ReloadRules(int client, int args)
{
    LoadRulesFile();
    ReplyToCommand(client, "[Rules] Reloaded rules.txt from disk (%d line(s)).", g_iRuleLineCount);
    return Plugin_Handled;
}

// ---------------------------------------------------------------------
// Text helpers
// ---------------------------------------------------------------------

// Word-wraps 'text' into lines of at most 'width' characters. A '\n' in the
// text starts a new paragraph, with a blank spacer line (" ") between
// paragraphs. Every line after the first gets 'indent' in front of it.
// Returns the number of lines written to 'lines'.
int WrapText(const char[] text, char[][] lines, int maxLines, int lineSize, int width, const char[] indent)
{
    char sLine[128];
    char sWord[128];

    int  count      = 0;
    int  len        = strlen(text);
    int  pos        = 0;
    bool bFirstPara = true;

    while (pos <= len)
    {
        int paraEnd = pos;
        while (paraEnd < len && text[paraEnd] != '\n')
        {
            paraEnd++;
        }

        if (!bFirstPara)
        {
            if (count >= maxLines)
            {
                return count;
            }
            strcopy(lines[count], lineSize, " ");
            count++;
        }
        bFirstPara = false;

        if (count > 0)
        {
            strcopy(sLine, sizeof(sLine), indent);
        }
        else
        {
            sLine[0] = '\0';
        }
        bool bHasWord = false;

        int p = pos;
        while (p < paraEnd)
        {
            while (p < paraEnd && text[p] == ' ')
            {
                p++;
            }
            if (p >= paraEnd)
            {
                break;
            }

            int wEnd = p;
            while (wEnd < paraEnd && text[wEnd] != ' ')
            {
                wEnd++;
            }

            int wLen = wEnd - p;
            if (wLen > sizeof(sWord) - 1)
            {
                wLen = sizeof(sWord) - 1;
            }
            strcopy(sWord, wLen + 1, text[p]);

            if (bHasWord && strlen(sLine) + 1 + wLen > width)
            {
                if (count >= maxLines)
                {
                    return count;
                }
                strcopy(lines[count], lineSize, sLine);
                count++;
                strcopy(sLine, sizeof(sLine), indent);
                bHasWord = false;
            }

            if (bHasWord)
            {
                StrCat(sLine, sizeof(sLine), " ");
            }
            StrCat(sLine, sizeof(sLine), sWord);
            bHasWord = true;

            p = wEnd;
        }

        if (bHasWord)
        {
            if (count >= maxLines)
            {
                return count;
            }
            strcopy(lines[count], lineSize, sLine);
            count++;
        }

        pos = paraEnd + 1;
    }

    return count;
}

// Appends lines[from .. to-1] to dest, separated by newlines.
void AppendLines(char[] dest, int destLen, const char[][] lines, int from, int to)
{
    for (int i = from; i < to; i++)
    {
        if (i > from)
        {
            StrCat(dest, destLen, "\n");
        }
        StrCat(dest, destLen, lines[i]);
    }
}

bool IsBlankLine(const char[] sLine)
{
    return (sLine[0] == ' ' && sLine[1] == '\0');
}

// The number shown on a rule's button: the number the rule text starts with
// ("7. Non-Participation..." -> 7), or its position in the file if it has none.
int GetRuleNumber(int rule)
{
    int n = 0;
    int i = 0;
    while (g_sRuleLines[rule][i] >= '0' && g_sRuleLines[rule][i] <= '9')
    {
        n = n * 10 + (g_sRuleLines[rule][i] - '0');
        i++;
    }
    return (i > 0) ? n : rule + 1;
}

// ---------------------------------------------------------------------
// Rules list menu
// ---------------------------------------------------------------------

int GetLinesPerPage()
{
    int n = g_cvLinesPerPage.IntValue;
    return (n < 1) ? 1 : n;
}

int GetTotalPages()
{
    int perPage = GetLinesPerPage();
    int pages = (g_iRuleLineCount + perPage - 1) / perPage;
    return (pages < 1) ? 1 : pages;
}

void ShowRulesMenu(int client, int page)
{
    int totalPages = GetTotalPages();

    if (page < 0)
    {
        page = 0;
    }
    if (page >= totalPages)
    {
        page = totalPages - 1;
    }
    g_iCurrentPage[client] = page;

    int perPage  = GetLinesPerPage();
    int startIdx = page * perPage;
    int endIdx   = startIdx + perPage;
    if (endIdx > g_iRuleLineCount)
    {
        endIdx = g_iRuleLineCount;
    }

    // The rules themselves are drawn as the menu's title text (wrapped, with
    // a blank line between rules); the buttons below are only for navigation
    // and for opening explanations.
    char sTitle[1024];
    if (totalPages > 1)
    {
        FormatEx(sTitle, sizeof(sTitle), "SERVER RULES (Page %d/%d)", page + 1, totalPages);
    }
    else
    {
        strcopy(sTitle, sizeof(sTitle), "SERVER RULES");
    }
    StrCat(sTitle, sizeof(sTitle), "\n");
    StrCat(sTitle, sizeof(sTitle), DIVIDER);

    char sWrapped[8][WRAP_LINE_SIZE];
    for (int i = startIdx; i < endIdx; i++)
    {
        StrCat(sTitle, sizeof(sTitle), (i == startIdx) ? "\n" : "\n \n");

        int n = WrapText(g_sRuleLines[i], sWrapped, 8, WRAP_LINE_SIZE, WRAP_WIDTH, "   ");
        AppendLines(sTitle, sizeof(sTitle), sWrapped, 0, n);
    }

    Menu menu = new Menu(MenuHandler_Rules);
    menu.ExitButton = true;
    menu.SetTitle("%s", sTitle);

    for (int i = startIdx; i < endIdx; i++)
    {
        if (g_sRuleExplain[i][0] == '\0')
        {
            continue;
        }

        char sInfo[8];
        IntToString(i, sInfo, sizeof(sInfo));

        char sDisplay[32];
        FormatEx(sDisplay, sizeof(sDisplay), "Explain rule %d", GetRuleNumber(i));
        menu.AddItem(sInfo, sDisplay);
    }

    if (page > 0)
    {
        menu.AddItem(MENUITEM_PREV, "<< Previous Page");
    }
    if (page < totalPages - 1)
    {
        menu.AddItem(MENUITEM_NEXT, "Next Page >>");
    }

    // A menu with no items can't be displayed, so give it a close button.
    if (menu.ItemCount == 0)
    {
        menu.AddItem(MENUITEM_CLOSE, "Close");
    }

    menu.Display(client, 60);
}

public int MenuHandler_Rules(Menu menu, MenuAction action, int client, int itemNum)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char sInfo[16];
            menu.GetItem(itemNum, sInfo, sizeof(sInfo));

            if (StrEqual(sInfo, MENUITEM_NEXT))
            {
                ShowRulesMenu(client, g_iCurrentPage[client] + 1);
            }
            else if (StrEqual(sInfo, MENUITEM_PREV))
            {
                ShowRulesMenu(client, g_iCurrentPage[client] - 1);
            }
            else if (StrEqual(sInfo, MENUITEM_CLOSE))
            {
                // Nothing to do - the menu closes itself.
            }
            else
            {
                ShowRuleDetail(client, StringToInt(sInfo), 0);
            }
        }

        case MenuAction_End:
        {
            delete menu;
        }
    }

    return 0;
}

// ---------------------------------------------------------------------
// Rule explanation menu (wrapped, and split into pages if it's long)
// ---------------------------------------------------------------------

void ShowRuleDetail(int client, int rule, int page)
{
    if (rule < 0 || rule >= g_iRuleLineCount || g_sRuleExplain[rule][0] == '\0')
    {
        ShowRulesMenu(client, g_iCurrentPage[client]);
        return;
    }

    char sWrapped[MAX_WRAP_LINES][WRAP_LINE_SIZE];
    int totalLines = WrapText(g_sRuleExplain[rule], sWrapped, MAX_WRAP_LINES, WRAP_LINE_SIZE, WRAP_WIDTH, "");
    if (totalLines < 1)
    {
        ShowRulesMenu(client, g_iCurrentPage[client]);
        return;
    }

    int totalPages = (totalLines + DETAIL_LINES_PER_PAGE - 1) / DETAIL_LINES_PER_PAGE;
    if (page < 0)
    {
        page = 0;
    }
    if (page >= totalPages)
    {
        page = totalPages - 1;
    }

    g_iDetailRule[client] = rule;
    g_iDetailPage[client] = page;

    int startLine = page * DETAIL_LINES_PER_PAGE;
    int endLine   = startLine + DETAIL_LINES_PER_PAGE;
    if (endLine > totalLines)
    {
        endLine = totalLines;
    }

    // Don't start or end a page on a blank spacer line.
    while (startLine < endLine && IsBlankLine(sWrapped[startLine]))
    {
        startLine++;
    }
    while (endLine > startLine && IsBlankLine(sWrapped[endLine - 1]))
    {
        endLine--;
    }

    char sHeader[8][WRAP_LINE_SIZE];
    int headerLines = WrapText(g_sRuleLines[rule], sHeader, 8, WRAP_LINE_SIZE, WRAP_WIDTH, "   ");

    char sTitle[1024];
    sTitle[0] = '\0';
    AppendLines(sTitle, sizeof(sTitle), sHeader, 0, headerLines);
    StrCat(sTitle, sizeof(sTitle), "\n");
    StrCat(sTitle, sizeof(sTitle), DIVIDER);
    StrCat(sTitle, sizeof(sTitle), "\n");
    AppendLines(sTitle, sizeof(sTitle), sWrapped, startLine, endLine);

    if (totalPages > 1)
    {
        char sFooter[32];
        FormatEx(sFooter, sizeof(sFooter), "\n \n(Part %d/%d)", page + 1, totalPages);
        StrCat(sTitle, sizeof(sTitle), sFooter);
    }

    Menu menu = new Menu(MenuHandler_RuleDetail);
    menu.ExitButton = true;
    menu.SetTitle("%s", sTitle);

    if (page > 0)
    {
        menu.AddItem(MENUITEM_PREV, "<< Previous");
    }
    if (page < totalPages - 1)
    {
        menu.AddItem(MENUITEM_NEXT, "Next >>");
    }
    menu.AddItem(MENUITEM_BACK, "Back to rules");

    menu.Display(client, 60);
}

public int MenuHandler_RuleDetail(Menu menu, MenuAction action, int client, int itemNum)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char sInfo[16];
            menu.GetItem(itemNum, sInfo, sizeof(sInfo));

            if (StrEqual(sInfo, MENUITEM_NEXT))
            {
                ShowRuleDetail(client, g_iDetailRule[client], g_iDetailPage[client] + 1);
            }
            else if (StrEqual(sInfo, MENUITEM_PREV))
            {
                ShowRuleDetail(client, g_iDetailRule[client], g_iDetailPage[client] - 1);
            }
            else
            {
                ShowRulesMenu(client, g_iCurrentPage[client]);
            }
        }

        case MenuAction_End:
        {
            delete menu;
        }
    }

    return 0;
}
