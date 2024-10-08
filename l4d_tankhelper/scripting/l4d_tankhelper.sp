//此插件0.3秒後設置Tank血量 (僅限此插件生成的tank)

#pragma semicolon 1
#pragma newdecls required //強制1.7以後的新語法
#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <left4dhooks>
#include <actions> // https://forums.alliedmods.net/showthread.php?t=336374
#include <spawn_infected_nolimit> //https://github.com/fbef0102/L4D1_2-Plugins/tree/master/spawn_infected_nolimit

public Plugin myinfo = 
{
	name = "Tanks throw special infected",
	author = "Pan Xiaohai & HarryPotter",
	description = "Tanks throw Tank/S.I./Witch/Hittable instead of rock",
	version = "2.5h-2024/8/27",
	url = "https://forums.alliedmods.net/showthread.php?t=140254"
}

int ZC_TANK;
int L4D2Version;
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) 
{
	EngineVersion test = GetEngineVersion();
	
	if( test == Engine_Left4Dead )
	{
		L4D2Version = false;
		ZC_TANK = 5;
	}
	else if( test == Engine_Left4Dead2 )
	{
		L4D2Version = true;
		ZC_TANK = 8;
	}
	else
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 1 & 2.");
		return APLRes_SilentFailure;
	}
	
	return APLRes_Success; 
}

#define MAXENTITIES                   2048
#define ENTITY_SAFE_LIMIT 2000 //don't spawn boxes when it's index is above this

#define PARTICLE_ELECTRICAL	"electrical_arc_01_system"

#define SOUND_THROWN_MISSILE 		"player/tank/attack/thrown_missile_loop_1.wav"

#define MAXENTITIES                   2048
#define ENTITY_SAFE_LIMIT 2000 //don't spawn boxes when it's index is above this

#define ZC_SMOKER	1
#define ZC_BOOMER	2
#define ZC_HUNTER	3
#define ZC_SPITTER	4
#define ZC_JOCKEY	5
#define ZC_CHARGER	6
#define ZC_WITCH 	7

#define EXPLOSION_SOUND		"animation/bombing_run_01.wav"

#define MODEL_fallen			"models/props_foliage/tree_trunk_fallen.mdl"
#define MODEL_rock				"models/props/cs_militia/militiarock01.mdl"
#define MODEL_cart2				"models/props_vehicles/airport_baggage_cart2.mdl"
#define MODEL_cara_95sedan		"models/props_vehicles/cara_95sedan.mdl"
#define MODEL_atlas_break_ball	"models/props_unique/airport/atlas_break_ball.mdl"
#define MODEL_forklift			"models/props/cs_assault/forklift_brokenlift.mdl"
#define MODEL_dumpster_2		"models/props_junk/dumpster_2.mdl"

ConVar l4d_tank_throw_si_ai, l4d_tank_throw_si_real, l4d_tank_throw_hunter, l4d_tank_throw_smoker, l4d_tank_throw_boomer,
	l4d_tank_throw_charger, l4d_tank_throw_spitter, l4d_tank_throw_jockey, l4d_tank_throw_tank, l4d_tank_throw_self,
	l4d_tank_throw_tank_health, l4d_tank_throw_witch, l4d_tank_throw_witch_health, l4d_tank_throw_car, l4d_tank_car_time,
	g_hWitchKillTime,
	l4d_tank_throw_hunter_limit, l4d_tank_throw_smoker_limit, l4d_tank_throw_boomer_limit,l4d_tank_throw_charger_limit, l4d_tank_throw_spitter_limit,
	l4d_tank_throw_jockey_limit,l4d_tank_throw_tank_limit,l4d_tank_throw_witch_limit;

ConVar z_tank_throw_force, z_max_player_zombies;
int g_iCvarMaxZombiePlayers;

enum eChance
{
	eChance_Hunter,
	eChance_Smoker,
	eChance_Boomer,
	eChance_Tank,
	eChance_Witch,
	eChance_self,
	eChance_Charger,
	eChance_Spitter,
	eChance_Jockey,
	eChance_Car,
	eChance_Max,
}

bool g_bIsTraceRock[MAXENTITIES +1];
int throw_tank_health, throw_witch_health, iThrowSILimit[9];
bool g_bSpawnWitchBride;
float fl4d_tank_throw_si_ai, fl4d_tank_throw_si_real, fl4d_tank_throw_witch,
	fThrowSIChance[eChance_Max], z_tank_throw_force_speed, g_fWitchKillTime, g_fCarKillTime;
Handle g_hNextBotPointer, g_hGetLocomotion, g_hJump;

static float g_99999Position[3] = {9999999.0, 9999999.0, 9999999.0};

int 
	g_iSetTankHealth[MAXPLAYERS+1];

public void OnPluginStart()
{
	GetGameData();

	z_tank_throw_force = FindConVar("z_tank_throw_force");
	z_max_player_zombies = FindConVar("z_max_player_zombies");

	l4d_tank_throw_si_ai = CreateConVar("l4d_tank_throw_si_ai", 						"100.0", 	"AI Tank throws helper special infected or car chance [0.0, 100.0]", FCVAR_NOTIFY, true, 0.0,true, 100.0); 
	l4d_tank_throw_si_real = CreateConVar("l4d_tank_throw_si_player", 					"70.0", 	"Real Tank Player throws helper special infected or car chance [0.0, 100.0]", FCVAR_NOTIFY, true, 0.0,true, 100.0); 
	l4d_tank_throw_hunter 	= CreateConVar("l4d_tank_throw_hunter", 					"5.0", 		"Weight of helper Hunter[0.0, 10.0]", FCVAR_NOTIFY, true, 0.0,true, 10.0); 
	l4d_tank_throw_smoker 	= CreateConVar("l4d_tank_throw_smoker", 					"5.0", 		"Weight of helper Smoker[0.0, 10.0]", FCVAR_NOTIFY, true, 0.0,true, 10.0); 
	l4d_tank_throw_boomer 	= CreateConVar("l4d_tank_throw_boomer", 					"5.0", 		"Weight of helper Boomer[0.0, 10.0]", FCVAR_NOTIFY, true, 0.0,true, 10.0); 
	if(L4D2Version)
	{
		l4d_tank_throw_charger 	= CreateConVar("l4d_tank_throw_charger", 				"5.0", 		"Weight of helper Charger [0.0, 10.0]", FCVAR_NOTIFY, true, 0.0,true, 10.0); 
		l4d_tank_throw_spitter	= CreateConVar("l4d_tank_throw_spitter", 				"5.0", 		"Weight of helper Spitter [0.0, 10.0]", FCVAR_NOTIFY, true, 0.0,true, 10.0); 
		l4d_tank_throw_jockey	= CreateConVar("l4d_tank_throw_jockey", 				"5.0",  	"Weight of helper Jockey [0.0, 10.0]", FCVAR_NOTIFY, true, 0.0,true, 10.0); 
	}
	l4d_tank_throw_tank	=	  CreateConVar("l4d_tank_throw_tank", 						"2.0",  	"Weight of helper Tank[0.0, 10.0]", FCVAR_NOTIFY, true, 0.0,true, 10.0); 
	l4d_tank_throw_self	= 	  CreateConVar("l4d_tank_throw_self", 						"10.0",  	"Weight of throwing Tank self[0.0, 10.0]", FCVAR_NOTIFY, true, 0.0,true, 10.0); 
	l4d_tank_throw_tank_health=CreateConVar("l4d_tank_throw_tank_health", 				"750",  	"Helper Tank bot health", FCVAR_NOTIFY, true, 1.0); 		
	l4d_tank_throw_witch	= CreateConVar("l4d_tank_throw_witch", 						"2.0",  	"Weight of helper Witch[0.0, 10.0]", FCVAR_NOTIFY, true, 0.0,true, 10.0); 
	l4d_tank_throw_witch_health=CreateConVar("l4d_tank_throw_witch_health", 			"250",  	"Helper Witch health", FCVAR_NOTIFY, true, 1.0); 	
	g_hWitchKillTime = CreateConVar("l4d_tank_throw_witch_lifespan", 					"30", 		"Amount of seconds before a helper witch is kicked. (only remove witches spawned by this plugin)", FCVAR_NOTIFY, true, 1.0);
	l4d_tank_throw_hunter_limit 	= CreateConVar("l4d_tank_throw_hunter_limit", 		"2", 		"Hunter Limit on the field[1 ~ 10] (if limit reached, throw Hunter teammate, if all hunters busy, throw Tank self)", FCVAR_NOTIFY, true, 1.0, true, 10.0); 
	l4d_tank_throw_smoker_limit 	= CreateConVar("l4d_tank_throw_smoker_limit", 		"2", 		"Smoker Limit on the field[1 ~ 10] (if limit reached, throw Smoker teammate, if all smokers busy, throw Tank self)", FCVAR_NOTIFY, true, 1.0, true,105.0); 
	l4d_tank_throw_boomer_limit 	= CreateConVar("l4d_tank_throw_boomer_limit", 		"2", 		"Boomer Limit on the field[1 ~ 10] (if limit reached, throw Boomer teammate)", FCVAR_NOTIFY, true, 1.0, true, 10.0); 
	if(L4D2Version)
	{
		l4d_tank_throw_charger_limit 	= CreateConVar("l4d_tank_throw_charger_limit", 	"2", 		"Charger Limit on the field[1 ~ 10] (if limit reached, throw Charger teammate, if all chargers busy, throw Tank self)", FCVAR_NOTIFY, true, 1.0, true, 10.0); 
		l4d_tank_throw_spitter_limit	= CreateConVar("l4d_tank_throw_spitter_limit", 	"1", 		"Spitter Limit on the field[1 ~ 10] (if limit reached, throw Spitter teammate)", FCVAR_NOTIFY, true, 1.0, true, 10.0); 
		l4d_tank_throw_jockey_limit		= CreateConVar("l4d_tank_throw_jockey_limit", 	"2",  		"Jockey Limit on the field[1 ~ 10] (if limit reached, throw Jockey teammate, if all jockeys busy, throw Tank self)", FCVAR_NOTIFY, true, 1.0, true, 10.0); 
	}
	l4d_tank_throw_tank_limit		= CreateConVar("l4d_tank_throw_tank_limit", 		"3",  		"Tank Limit on the field[1 ~ 10] (if limit reached, throw Tank teammate or yourself)", FCVAR_NOTIFY, true, 1.0, true, 10.0); 	
	l4d_tank_throw_witch_limit		= CreateConVar("l4d_tank_throw_witch_limit", 		"3",  		"Witch Limit on the field[1 ~ 10] (if limit reached, throw Tank self)", FCVAR_NOTIFY, true, 1.0, true, 10.0); 
	l4d_tank_throw_car				= CreateConVar("l4d_tank_throw_car", 				"5.0",  	"Weight of Hittable Car[0.0, 10.0]", FCVAR_NOTIFY, true, 0.0,true, 10.0); 
	l4d_tank_car_time				= CreateConVar("l4d_tank_throw_car_lifespan", 		"30.0",  	"Amount of seconds before a Hittable Car is removed (only remove hittable cars spawned by this plugin)", FCVAR_NOTIFY, true, 1.0); 

	AutoExecConfig(true, "l4d_tankhelper");
 
	GetConVar();
	z_tank_throw_force.AddChangeHook(ConVarChange);
	z_max_player_zombies.AddChangeHook(ConVarChange);
	l4d_tank_throw_si_ai.AddChangeHook(ConVarChange);
	l4d_tank_throw_si_real.AddChangeHook(ConVarChange);
	l4d_tank_throw_hunter.AddChangeHook(ConVarChange);
	l4d_tank_throw_smoker.AddChangeHook(ConVarChange);
	l4d_tank_throw_boomer.AddChangeHook(ConVarChange);
	if(L4D2Version)
	{
		l4d_tank_throw_charger.AddChangeHook(ConVarChange);
		l4d_tank_throw_spitter.AddChangeHook(ConVarChange);
		l4d_tank_throw_jockey.AddChangeHook(ConVarChange);
	}
	l4d_tank_throw_tank.AddChangeHook(ConVarChange);
	l4d_tank_throw_self.AddChangeHook(ConVarChange);
	l4d_tank_throw_tank_health.AddChangeHook(ConVarChange);
	l4d_tank_throw_witch.AddChangeHook(ConVarChange);
	l4d_tank_throw_witch_health.AddChangeHook(ConVarChange);
	g_hWitchKillTime.AddChangeHook(ConVarChange);
	l4d_tank_throw_hunter_limit.AddChangeHook(ConVarChange);
	l4d_tank_throw_smoker_limit.AddChangeHook(ConVarChange);
	l4d_tank_throw_boomer_limit.AddChangeHook(ConVarChange);
	if(L4D2Version)
	{
		l4d_tank_throw_charger_limit.AddChangeHook(ConVarChange);
		l4d_tank_throw_spitter_limit.AddChangeHook(ConVarChange);
		l4d_tank_throw_jockey_limit.AddChangeHook(ConVarChange);
	}
	l4d_tank_throw_tank_limit.AddChangeHook(ConVarChange);
	l4d_tank_throw_witch_limit.AddChangeHook(ConVarChange);
	l4d_tank_throw_car.AddChangeHook(ConVarChange);
	l4d_tank_car_time.AddChangeHook(ConVarChange);

	HookEvent("bot_player_replace", Event_PlayerReplaceBot);

	AddNormalSoundHook(OnNormalSoundPlay);
}

public void OnMapStart()
{ 
	if(L4D2Version)
	{ 
		PrecacheParticle(PARTICLE_ELECTRICAL);
	}

	g_bSpawnWitchBride = false;
	char sMap[64];
	GetCurrentMap(sMap, sizeof(sMap));
	if(StrEqual("c6m1_riverbank", sMap, false))
		g_bSpawnWitchBride = true;

	PrecacheSound(EXPLOSION_SOUND, true);

	PrecacheModel(MODEL_fallen, true);
	PrecacheModel(MODEL_rock, true);
	PrecacheModel(MODEL_cart2, true);
	PrecacheModel(MODEL_cara_95sedan, true);
	PrecacheModel(MODEL_atlas_break_ball, true);
	PrecacheModel(MODEL_forklift, true);
	PrecacheModel(MODEL_dumpster_2, true);
}

void ConVarChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	GetConVar();

}
void GetConVar()
{
	z_tank_throw_force_speed = z_tank_throw_force.FloatValue;
	g_iCvarMaxZombiePlayers = z_max_player_zombies.IntValue;

	fl4d_tank_throw_si_ai = l4d_tank_throw_si_ai.FloatValue;
	fl4d_tank_throw_si_real = l4d_tank_throw_si_real.FloatValue;
	fl4d_tank_throw_witch = l4d_tank_throw_witch.FloatValue;
	fThrowSIChance[eChance_Hunter]=l4d_tank_throw_hunter.FloatValue;
	fThrowSIChance[eChance_Smoker]=fThrowSIChance[eChance_Hunter]+l4d_tank_throw_smoker.FloatValue;
	fThrowSIChance[eChance_Boomer]=fThrowSIChance[eChance_Smoker]+l4d_tank_throw_boomer.FloatValue;
	fThrowSIChance[eChance_Tank]=fThrowSIChance[eChance_Boomer]+l4d_tank_throw_tank.FloatValue;	
	fThrowSIChance[eChance_Witch]=fThrowSIChance[eChance_Tank]+l4d_tank_throw_witch.FloatValue;
	fThrowSIChance[eChance_self]=fThrowSIChance[eChance_Witch]+l4d_tank_throw_self.FloatValue;
	if(L4D2Version)
	{
		fThrowSIChance[eChance_Charger]=fThrowSIChance[eChance_self]+l4d_tank_throw_charger.FloatValue;
		fThrowSIChance[eChance_Spitter]=fThrowSIChance[eChance_Charger]+l4d_tank_throw_spitter.FloatValue;
		fThrowSIChance[eChance_Jockey]=fThrowSIChance[eChance_Spitter]+l4d_tank_throw_jockey.FloatValue;
	}
	iThrowSILimit[0]=l4d_tank_throw_hunter_limit.IntValue;
	iThrowSILimit[1]=l4d_tank_throw_smoker_limit.IntValue;
	iThrowSILimit[2]=l4d_tank_throw_boomer_limit.IntValue;
	iThrowSILimit[3]=l4d_tank_throw_tank_limit.IntValue;
	iThrowSILimit[4]=l4d_tank_throw_witch_limit.IntValue;
	iThrowSILimit[5]=0; // no use
	if(L4D2Version)
	{
		iThrowSILimit[6]=l4d_tank_throw_charger_limit.IntValue;
		iThrowSILimit[7]=l4d_tank_throw_spitter_limit.IntValue;
		iThrowSILimit[8]=l4d_tank_throw_jockey_limit.IntValue;
	}

	throw_tank_health = l4d_tank_throw_tank_health.IntValue;
	throw_witch_health = l4d_tank_throw_witch_health.IntValue;
	g_fWitchKillTime = g_hWitchKillTime.FloatValue;

	fThrowSIChance[eChance_Car]=fThrowSIChance[eChance_Jockey]+l4d_tank_throw_car.FloatValue;

	g_fCarKillTime = l4d_tank_car_time.FloatValue;
}

// Sourcemod API Forward-------------------------------

public void OnClientDisconnect(int client) 
{
	g_iSetTankHealth[client] = 0;
}

//-------------------------------Left4Dhooks API Forward-------------------------------

public void L4D_TankRock_OnRelease_Post(int tank, int rock, const float vecPos[3], const float vecAng[3], const float vecVel[3], const float vecRot[3])
{
	if(tank < 0 || g_bIsTraceRock[rock])
	{
		g_bIsTraceRock[rock] = false;
		return;
	}

	float random = GetRandomFloat(1.0, 100.0);
	if( (IsFakeClient(tank) && random <= fl4d_tank_throw_si_ai) ||
		(!IsFakeClient(tank) && random <= fl4d_tank_throw_si_real) )
	{
		if(IsRockStuck(rock, vecPos) == false)
		{
			float velocity[3];
			velocity[0] = vecVel[0]; velocity[1] = vecVel[1]; velocity[2] = vecVel[2];
			
			NormalizeVector(velocity, velocity);
			ScaleVector(velocity, z_tank_throw_force_speed * 1.4);
			int new_helper = CreateSI(tank, vecPos, vecAng, velocity);
			if(new_helper > 0)
			{
				TeleportEntity(rock, g_99999Position);
				RemoveEdict(rock);
				if(L4D2Version) DisplayParticle(0, PARTICLE_ELECTRICAL, vecPos, NULL_VECTOR);    
				if(new_helper <= MaxClients) L4D_WarpToValidPositionIfStuck(new_helper);
			}
		}
	}
}

//-------------------------------Other API Forward-------------------------------

// from l4d_tracerock.smx by Harry, Tank's rock will trace survivor until hit something.
public void L4D_OnTraceRockCreated(int tank, int rock)
{
	g_bIsTraceRock[rock] = true;
}

//-------------------------------Sound Hook-------------------------------

Action OnNormalSoundPlay(int Clients[64], int &NumClients, char StrSample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level,
	int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if (StrEqual(StrSample, SOUND_THROWN_MISSILE, false)) {
		NumClients = 0;
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

// Event-------------------------------

void Event_PlayerReplaceBot(Event event, const char[] name, bool dontBroadcast)
{
	int bot = GetClientOfUserId(event.GetInt("bot"));
	int player = GetClientOfUserId(event.GetInt("player"));
	if (bot > 0 && bot <= MaxClients && IsClientInGame(bot) && player > 0 && player <= MaxClients && IsClientInGame(player)) 
	{
		if(g_iSetTankHealth[bot] > 0)
		{
			// 0.3秒後設置Tank血量
			DataPack hPack;
			CreateDataTimer(0.3, tmrTankSpawn, hPack, TIMER_FLAG_NO_MAPCHANGE);
			hPack.WriteCell(g_iSetTankHealth[bot]);
			hPack.WriteCell(GetClientUserId(player));

			g_iSetTankHealth[bot] = 0;
		}
	}
}

// Function-------------------------------

bool IsRockStuck(int ent, const float pos[3])
{
	float vAngles[3];
	float vOrigin[3];
	vAngles[2]=1.0;
	GetVectorAngles(vAngles, vAngles);
	Handle trace = TR_TraceRayFilterEx(pos, vAngles, MASK_SOLID, RayType_Infinite, TraceRayDontHitSelf,ent);

	if(TR_DidHit(trace))
	{
		TR_GetEndPosition(vOrigin, trace);
	 	float dis=GetVectorDistance(vOrigin, pos);
		if(dis>100.0)
		{
			delete trace;
			return false;
		}
	}
	
	delete trace;
	return true;
}

stock int CreateSI(int thetank, const float pos[3], const float ang[3], const float velocity[3])
{
	int selected=0;
	int chooseclass=0;
	float random = GetRandomFloat(1.0, fThrowSIChance[eChance_self]);
	if(L4D2Version) random = GetRandomFloat(1.0, fThrowSIChance[eChance_Car]);
	
	// current count ...
	int boomers=0;
	int smokers=0;
	int hunters=0;
	int spitters=0;
	int jockeys=0;
	int chargers=0;
	int tanks=0;
	int infectedfreeplayer = 0;
	int iClientCount = 0, iClients[MAXPLAYERS+1];
	for (int i=1;i<=MaxClients;i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == L4D_TEAM_INFECTED)
		{
			if (IsPlayerAlive(i))
			{
				// We count depending on class ...
				if (IsPlayerSmoker(i))
					smokers++;
				else if (IsPlayerBoomer(i))
					boomers++;	
				else if (IsPlayerHunter(i))
					hunters++;	
				else if (IsPlayerTank(i))
					tanks++;	
				else if (L4D2Version && IsPlayerSpitter(i))
					spitters++;	
				else if (L4D2Version && IsPlayerJockey(i))
					jockeys++;	
				else if (L4D2Version && IsPlayerCharger(i))
					chargers++;	

				continue;
			}

			if(!IsFakeClient(i))
			{
				iClients[iClientCount++] = i;
			}
		}
	}

	bool bOverLimit;
	if( (smokers+boomers+hunters+tanks+spitters+jockeys+chargers >= g_iCvarMaxZombiePlayers + 2) ||
		(smokers+boomers+hunters+tanks+spitters+jockeys+chargers >= MaxClients) )
	{
		bOverLimit = true;
	}

	infectedfreeplayer = (iClientCount == 0) ? 0 : iClients[GetRandomInt(0, iClientCount - 1)];

	int witches =0;
	int entity = MaxClients + 1;
	while ( ((entity = FindEntityByClassname(entity, "witch")) != -1) )
	{
		if(!IsValidEntity(entity)) continue;

		witches++;
	}

	bool bSpawnSuccessful = false;
	if(random<=fThrowSIChance[eChance_Hunter] && l4d_tank_throw_hunter.FloatValue > 0.0)
	{
		if(!bOverLimit && hunters < iThrowSILimit[0])
		{
			if(infectedfreeplayer > 0)
			{
				L4D_State_Transition(infectedfreeplayer, STATE_OBSERVER_MODE);
				L4D_BecomeGhost(infectedfreeplayer);
				L4D_SetClass(infectedfreeplayer, ZC_HUNTER);

				if(IsPlayerAlive(infectedfreeplayer))
				{
					selected = infectedfreeplayer;
					bSpawnSuccessful = true;
				}
			}
			else 
			{
				selected = NoLimit_CreateInfected("hunter", pos, NULL_VECTOR);
				if(selected > 0) bSpawnSuccessful = true;
			}
		}
		else
		{
			return -1;
		}
		
		chooseclass = ZC_HUNTER;
	}
	else if(random<=fThrowSIChance[eChance_Smoker] && l4d_tank_throw_smoker.FloatValue > 0.0)
	{
		if(!bOverLimit && smokers < iThrowSILimit[1])
		{
			if(infectedfreeplayer > 0)
			{
				L4D_State_Transition(infectedfreeplayer, STATE_OBSERVER_MODE);
				L4D_BecomeGhost(infectedfreeplayer);
				L4D_SetClass(infectedfreeplayer, ZC_SMOKER);

				if(IsPlayerAlive(infectedfreeplayer))
				{
					selected = infectedfreeplayer;
					bSpawnSuccessful = true;
				}
			}
			else 
			{
				selected = NoLimit_CreateInfected("smoker", pos, NULL_VECTOR);
				if(selected > 0) bSpawnSuccessful = true;
			}
		}

		chooseclass = ZC_SMOKER;
	}
	else if(random<=fThrowSIChance[eChance_Boomer] && l4d_tank_throw_boomer.FloatValue > 0.0)
	{
		if(!bOverLimit && boomers < iThrowSILimit[2])
		{
			if(infectedfreeplayer > 0)
			{
				L4D_State_Transition(infectedfreeplayer, STATE_OBSERVER_MODE);
				L4D_BecomeGhost(infectedfreeplayer);
				L4D_SetClass(infectedfreeplayer, ZC_BOOMER);

				if(IsPlayerAlive(infectedfreeplayer))
				{
					selected = infectedfreeplayer;
					bSpawnSuccessful = true;
				}
			}
			else 
			{
				selected = NoLimit_CreateInfected("boomer", pos, NULL_VECTOR);
				if(selected > 0) bSpawnSuccessful = true;
			}
		}

		chooseclass = ZC_BOOMER;
	}
	else if(random<=fThrowSIChance[eChance_Tank] && l4d_tank_throw_tank.FloatValue > 0.0)
	{
		if(!bOverLimit && tanks < iThrowSILimit[3])
		{
			if(infectedfreeplayer > 0)
			{
				L4D_State_Transition(infectedfreeplayer, STATE_OBSERVER_MODE);
				L4D_BecomeGhost(infectedfreeplayer);
				L4D_SetClass(infectedfreeplayer, ZC_TANK);

				if(IsPlayerAlive(infectedfreeplayer))
				{
					selected = infectedfreeplayer;
					bSpawnSuccessful = true;
				}
			}
			else
			{
				selected = NoLimit_CreateInfected("tank", pos, NULL_VECTOR);
				if(selected > 0)
				{
					SetClientInfo(selected, "name", "helper Tank");
					bSpawnSuccessful = true;
				}
			}
		}

		chooseclass = ZC_TANK; 
	}
	else if(random<=fThrowSIChance[eChance_Witch] && l4d_tank_throw_witch.FloatValue > 0.0)
	{
		if(witches < iThrowSILimit[4])
		{
			if( g_bSpawnWitchBride )
			{
				selected = L4D2_SpawnWitchBride(pos, NULL_VECTOR);
			}
			else
			{
				selected = L4D2_SpawnWitch(pos, NULL_VECTOR);
			}
			if(selected > MaxClients)
			{
				SetEntProp(selected, Prop_Data, "m_iHealth", throw_witch_health);
				ForceWitchJump(selected, velocity, true);
				
				CreateTimer(g_fWitchKillTime, KickWitch_Timer, EntIndexToEntRef(selected), TIMER_FLAG_NO_MAPCHANGE);
				return selected;
			}
		}
		else
		{
			selected = thetank;
		}

		chooseclass = ZC_WITCH;
	}
	else if(random<=fThrowSIChance[eChance_self] && l4d_tank_throw_self.FloatValue > 0.0)
	{
		selected=thetank;
	}
	else if(random<=fThrowSIChance[eChance_Charger] && l4d_tank_throw_charger.FloatValue > 0.0)
	{
		if(!bOverLimit && chargers < iThrowSILimit[6])
		{
			if(infectedfreeplayer > 0)
			{
				L4D_State_Transition(infectedfreeplayer, STATE_OBSERVER_MODE);
				L4D_BecomeGhost(infectedfreeplayer);
				L4D_SetClass(infectedfreeplayer, ZC_CHARGER);

				if(IsPlayerAlive(infectedfreeplayer))
				{
					selected = infectedfreeplayer;
					bSpawnSuccessful = true;
				}
			}
			else
			{
				selected = NoLimit_CreateInfected("charger", pos, NULL_VECTOR);
				if(selected > 0) bSpawnSuccessful = true;
			}
		}

		chooseclass = ZC_CHARGER;
	}
	else if(random<=fThrowSIChance[eChance_Spitter] && l4d_tank_throw_spitter.FloatValue > 0.0)
	{
		if(!bOverLimit && spitters < iThrowSILimit[7])
		{
			if(infectedfreeplayer > 0)
			{
				L4D_State_Transition(infectedfreeplayer, STATE_OBSERVER_MODE);
				L4D_BecomeGhost(infectedfreeplayer);
				L4D_SetClass(infectedfreeplayer, ZC_SPITTER);

				if(IsPlayerAlive(infectedfreeplayer))
				{
					selected = infectedfreeplayer;
					bSpawnSuccessful = true;
				}
			}
			else
			{
				selected = NoLimit_CreateInfected("spitter", pos, NULL_VECTOR);
				if(selected > 0) bSpawnSuccessful = true;
			}
		}

		chooseclass = ZC_SPITTER;
	}
	else if(random<=fThrowSIChance[eChance_Jockey] && l4d_tank_throw_jockey.FloatValue > 0.0)
	{
		if(!bOverLimit && jockeys < iThrowSILimit[8])
		{
			if(infectedfreeplayer > 0)
			{
				L4D_State_Transition(infectedfreeplayer, STATE_OBSERVER_MODE);
				L4D_BecomeGhost(infectedfreeplayer);
				L4D_SetClass(infectedfreeplayer, ZC_JOCKEY);

				if(IsPlayerAlive(infectedfreeplayer))
				{
					selected = infectedfreeplayer;
					bSpawnSuccessful = true;
				}
			}
			else
			{
				selected = NoLimit_CreateInfected("jockey", pos, NULL_VECTOR);
				if(selected > 0) bSpawnSuccessful = true;
			}
		}

		chooseclass = ZC_JOCKEY;
	}
	else if(random<=fThrowSIChance[eChance_Car] && l4d_tank_throw_car.FloatValue > 0.0)
	{
		int physics = CreateEntityByName("prop_physics_multiplayer");
		if (CheckIfEntityMax( physics ) == false)
			return -1;

		switch(GetRandomInt(0, 6))
		{
			case 0: SetEntityModel(physics, MODEL_fallen);
			case 1: SetEntityModel(physics, MODEL_rock);
			case 2: SetEntityModel(physics, MODEL_cart2);
			case 3: SetEntityModel(physics, MODEL_cara_95sedan);
			case 4: SetEntityModel(physics, MODEL_atlas_break_ball);
			case 5: SetEntityModel(physics, MODEL_forklift);
			case 6: SetEntityModel(physics, MODEL_dumpster_2);
		}

		DispatchSpawn(physics);
		TeleportEntity(physics, pos, NULL_VECTOR, velocity);

		SetEntPropEnt(physics, Prop_Data, "m_hPhysicsAttacker", thetank);
		SetEntPropFloat(physics, Prop_Data, "m_flLastPhysicsInfluenceTime", GetEngineTime());
		CreateTimer(g_fCarKillTime, Timer_KillCar, EntIndexToEntRef(physics), TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(2.0, Timer_NormalVelocity, EntIndexToEntRef(physics), TIMER_FLAG_NO_MAPCHANGE);

		EmitSoundToAll(EXPLOSION_SOUND, physics);

		return physics;
	}
	else
	{
		return -1;
	}

	if (bSpawnSuccessful && selected > 0 && selected <= MaxClients) // SpawnSuccessful (AI/Real Player)
	{
		L4D_MaterializeFromGhost(selected);

		if(infectedfreeplayer == selected)
		{
			TeleportEntity(infectedfreeplayer, pos, NULL_VECTOR, velocity);
		}
		else
		{
			TeleportEntity(selected, pos, NULL_VECTOR, velocity);
		}

		if(chooseclass == ZC_TANK)
		{
			SetEntProp(selected, Prop_Data, "m_iHealth", throw_tank_health);
			SetEntProp(selected, Prop_Data, "m_iMaxHealth", throw_tank_health);

			g_iSetTankHealth[selected] = throw_tank_health;

			// 0.3秒後設置Tank血量
			DataPack hPack;
			CreateDataTimer(0.3, tmrTankSpawn, hPack, TIMER_FLAG_NO_MAPCHANGE);
			hPack.WriteCell(throw_tank_health);
			hPack.WriteCell(GetClientUserId(selected));
		}
	}
	else if (selected == 0) //throw teammate
	{
		int andidate[MAXPLAYERS+1];
		int index=0;
		for(int i = 1; i <= MaxClients; i++)
		{	
			if(IsClientInGame(i) && IsPlayerAlive(i) && !IsPlayerGhost(i) && GetClientTeam(i) == L4D_TEAM_INFECTED && L4D_GetSurvivorVictim(i) == -1)
			{
				if(GetEntProp(i,Prop_Send,"m_zombieClass") == chooseclass)
				{
					andidate[index++] = i;
				}
			}		 
		}

		if(index > 0) selected = andidate[GetRandomInt(0, index-1)];
		else selected = thetank; //all infected busy, throw tank self
		
		if (selected > 0) TeleportEntity(selected, pos, NULL_VECTOR, velocity);
	}
	else
	{
		return -1;
	}

	/*PrintToChatAll("%d (%d) was throw: %.2f %.2f %.2f %.2f %.2f %.2f", 
		selected, chooseclass, pos[0], pos[1], pos[2], velocity[0], velocity[1], velocity[2]);*/
 
 	return selected;
}

int DisplayParticle(int target, const char[] sParticle, const float vPos[3], const float vAng[3], float refire = 0.0)
{
	int entity = CreateEntityByName("info_particle_system");
	if( CheckIfEntitySafe(entity) == false)
	{
		return 0;
	}

	DispatchKeyValue(entity, "effect_name", sParticle);
	DispatchSpawn(entity);
	ActivateEntity(entity);
	AcceptEntityInput(entity, "start");

	// Attach
	if( target )
	{
		SetVariantString("!activator");
		AcceptEntityInput(entity, "SetParent", target);
	}

	TeleportEntity(entity, vPos, vAng, NULL_VECTOR);

	// Refire
	if( refire )
	{
		static char sTemp[64];
		Format(sTemp, sizeof(sTemp), "OnUser1 !self:Stop::%f:-1", refire - 0.05);
		SetVariantString(sTemp);
		AcceptEntityInput(entity, "AddOutput");
		Format(sTemp, sizeof(sTemp), "OnUser1 !self:FireUser2::%f:-1", refire);
		SetVariantString(sTemp);
		AcceptEntityInput(entity, "AddOutput");
		AcceptEntityInput(entity, "FireUser1");

		SetVariantString("OnUser2 !self:Start::0:-1");
		AcceptEntityInput(entity, "AddOutput");
		SetVariantString("OnUser2 !self:FireUser1::0:-1");
		AcceptEntityInput(entity, "AddOutput");
	}
	
	CreateTimer(3.0, DeleteParticles, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);

	return entity;
}

Action DeleteParticles(Handle timer, any particle)
{
	particle = EntRefToEntIndex(particle);
	if (particle != INVALID_ENT_REFERENCE)
	{
		AcceptEntityInput(particle, "stop");
		AcceptEntityInput(particle, "kill");
	}

	return Plugin_Continue;
}

bool TraceRayDontHitSelf(int entity, int mask, any data)
{
	if(entity == data) 
	{
		return false; 
	}
	return true;
}
 
int PrecacheParticle(const char[] sEffectName)
{
	static int table = INVALID_STRING_TABLE;
	if( table == INVALID_STRING_TABLE )
	{
		table = FindStringTable("ParticleEffectNames");
	}

	int index = FindStringIndex(table, sEffectName);
	if( index == INVALID_STRING_INDEX )
	{
		bool save = LockStringTables(false);
		AddToStringTable(table, sEffectName);
		LockStringTables(save);
		index = FindStringIndex(table, sEffectName);
	}

	return index;
}

Handle hGameConf;
void GetGameData()
{
	hGameConf = LoadGameConfigFile("l4d_tank_helper");
	if( hGameConf != null )
	{
		int offset = GameConfGetOffset(hGameConf, "NextBotPointer");
		if(offset == -1) {SetFailState("Unable to find NextBotPointer offset.");return;}
		StartPrepSDKCall(SDKCall_Entity);
		PrepSDKCall_SetVirtual(offset);
		PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
		g_hNextBotPointer = EndPrepSDKCall();
		if(g_hNextBotPointer==null) {SetFailState("Cannot initialize NextBotPointer SDKCall, signature is broken.");return;}

		offset = GameConfGetOffset(hGameConf, "GetLocomotion");
		if(offset == -1) {SetFailState("Unable to find GetLocomotion offset.");return;}
		StartPrepSDKCall(SDKCall_Raw);
		PrepSDKCall_SetVirtual(offset);
		PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
		g_hGetLocomotion = EndPrepSDKCall();
		if(g_hGetLocomotion==null) {SetFailState("Cannot initialize GetLocomotion SDKCall, signature is broken.");return;}

		offset = GameConfGetOffset(hGameConf, "Jump");
		if(offset == -1) {SetFailState("Unable to find Jump offset.");return;}
		StartPrepSDKCall(SDKCall_Raw);
		PrepSDKCall_SetVirtual(offset);
		g_hJump = EndPrepSDKCall();
		if(g_hJump==null) {SetFailState("Cannot initialize Jump SDKCall, signature is broken.");return;}
	}
	else
	{
		SetFailState("Unable to find l4d_tank_helper.txt gamedata file.");
	}
	delete hGameConf;
}

stock int FindRandomTank(int exclude) 
{
	int iClientCount, iClients[MAXPLAYERS+1];
	for (int i = 1; i <= MaxClients; i++) 
	{
		if (i != exclude && IsClientInGame(i) && GetClientTeam(i) == L4D_TEAM_INFECTED && IsPlayerAlive(i) && GetEntProp(i,Prop_Send,"m_zombieClass") == ZC_TANK)
		{
			iClients[iClientCount++] = i;
		}
	}

	return (iClientCount == 0) ? 0 : iClients[GetRandomInt(0, iClientCount - 1)];
}

int L4D_GetSurvivorVictim(int client)
{
	int victim;

	if(L4D2Version)
	{
		/* Charger */
		victim = GetEntPropEnt(client, Prop_Send, "m_pummelVictim");
		if (victim > 0)
		{
			return victim;
		}

		victim = GetEntPropEnt(client, Prop_Send, "m_carryVictim");
		if (victim > 0)
		{
			return victim;
		}

		/* Jockey */
		victim = GetEntPropEnt(client, Prop_Send, "m_jockeyVictim");
		if (victim > 0)
		{
			return victim;
		}
	}

    /* Hunter */
	victim = GetEntPropEnt(client, Prop_Send, "m_pounceVictim");
	if (victim > 0)
	{
		return victim;
 	}

    /* Smoker */
 	victim = GetEntPropEnt(client, Prop_Send, "m_tongueVictim");
	if (victim > 0)
	{
		return victim;	
	}

	return -1;
}


Action tmrTankSpawn(Handle timer, DataPack hPack) {
	hPack.Reset();
	int setTankHealth = hPack.ReadCell();
	int throwTank = GetClientOfUserId(hPack.ReadCell());

	g_iSetTankHealth[throwTank] = 0;

	if (!throwTank || !IsClientInGame(throwTank) || GetClientTeam(throwTank) != 3 || !IsPlayerAlive(throwTank) || !IsPlayerTank(throwTank))
		return Plugin_Continue;

	SetEntProp(throwTank, Prop_Data, "m_iHealth", setTankHealth);
	SetEntProp(throwTank, Prop_Data, "m_iMaxHealth", setTankHealth);

	//PrintToChatAll("tmrTankSpawn: %d - %N", setTankHealth, throwTank);

	return Plugin_Continue;
}

Action KickWitch_Timer(Handle timer, int ref)
{
	if(IsValidEntRef(ref))
	{
		int entity = EntRefToEntIndex(ref);
		bool bKill = true;
		float clientOrigin[3];
		float witchOrigin[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", witchOrigin);
		for (int i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i) && GetClientTeam(i) == L4D_TEAM_SURVIVOR && IsPlayerAlive(i))
			{
				GetClientAbsOrigin(i, clientOrigin);
				if (GetVectorDistance(clientOrigin, witchOrigin, true) < Pow(300.0,2.0))
				{
					bKill = false;
					break;
				}
			}
		}

		if(bKill)
		{
			AcceptEntityInput(ref, "kill"); //remove witch
			return Plugin_Stop;
		}
		else
		{
			CreateTimer(g_fWitchKillTime, KickWitch_Timer, ref, TIMER_FLAG_NO_MAPCHANGE);
			return Plugin_Continue;
		}
	}

	return Plugin_Stop;
}

bool IsValidEntRef(int entity)
{
	if( entity && EntRefToEntIndex(entity) != INVALID_ENT_REFERENCE)
		return true;
	return false;
}

bool IsPlayerSmoker (int client)
{
	if(GetEntProp(client,Prop_Send,"m_zombieClass") == ZC_SMOKER)
		return true;
	return false;
}

bool IsPlayerHunter (int client)
{
	if(GetEntProp(client,Prop_Send,"m_zombieClass") == ZC_HUNTER)
		return true;
	return false;
}

bool IsPlayerBoomer (int client)
{
	if(GetEntProp(client,Prop_Send,"m_zombieClass") == ZC_BOOMER)
		return true;
	return false;
}

bool IsPlayerSpitter (int client)
{
	if(GetEntProp(client,Prop_Send,"m_zombieClass") == ZC_SPITTER)
		return true;
	return false;
}

bool IsPlayerJockey (int client)
{
	if(GetEntProp(client,Prop_Send,"m_zombieClass") == ZC_JOCKEY)
		return true;
	return false;
}

bool IsPlayerCharger (int client)
{
	if(GetEntProp(client,Prop_Send,"m_zombieClass") == ZC_CHARGER)
		return true;
	return false;
}

bool IsPlayerTank (int client)
{
	if(GetEntProp(client,Prop_Send,"m_zombieClass") == ZC_TANK)
		return true;
	return false;
}

bool IsPlayerGhost (int client)
{
	if (GetEntProp(client, Prop_Send, "m_isGhost"))
		return true;
	return false;
}

bool CheckIfEntityMax(int entity)
{
	if(entity == -1) return false;

	if(	entity > ENTITY_SAFE_LIMIT)
	{
		RemoveEntity(entity);
		return false;
	}
	return true;
}

Action Timer_KillCar(Handle timer, int ref)
{
	int entity = EntRefToEntIndex(ref);
	if(entity != INVALID_ENT_REFERENCE)
	{
		RemoveEntity(entity);
	}

	return Plugin_Continue;
}

Action Timer_NormalVelocity(Handle timer, int ref)
{
	int entity = EntRefToEntIndex(ref);
	if(entity != INVALID_ENT_REFERENCE)
	{
		float vel[3];
		SetEntPropVector(entity, Prop_Data, "m_vecVelocity", vel);
		TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, vel);
	}

	return Plugin_Continue;
}

bool CheckIfEntitySafe(int entity)
{
	if(entity == -1) return false;

	if(	entity > ENTITY_SAFE_LIMIT)
	{
		RemoveEntity(entity);
		return false;
	}
	return true;
}

// Teleport witch and make her move
// -----------by BHaType: https://forums.alliedmods.net/showpost.php?p=2771305&postcount=2

void ForceWitchJump( int witch, const float vVelocity[3], bool add = false )
{
    Address locomotion = GetLocomotion(witch);
    
    if ( !locomotion )
        return;
    
    float vVec[3];
    
    if ( add )
        GetWitchVelocity(locomotion, vVec);

    AddVectors(vVec, vVelocity, vVec);
    
    Jump(witch, locomotion);
    SetWitchVelocity(locomotion, vVec);
}

stock void Jump( int witch, Address locomotion )
{
	if(L4D2Version)
		StoreToAddress(locomotion + view_as<Address>(0xC0), 0, NumberType_Int8);
	else 
		StoreToAddress(locomotion + view_as<Address>(0xB4), 0, NumberType_Int8);

	SDKCall(g_hJump, locomotion);
}

void GetWitchVelocity( Address locomotion, float out[3] )
{
	if(L4D2Version)
	{
		for (int i; i <= 2; i++)
			out[i] = view_as<float>(LoadFromAddress(locomotion + view_as<Address>(0x6C + i * 4), NumberType_Int32));
	}
	else
	{
		for (int i; i <= 2; i++)
			out[i] = view_as<float>(LoadFromAddress(locomotion + view_as<Address>(0x60 + i * 4), NumberType_Int32));
	}
}

void SetWitchVelocity( Address locomotion, const float vVelocity[3] )
{
	if(L4D2Version)
	{
		for (int i; i <= 2; i++)
			StoreToAddress(locomotion + view_as<Address>(0x6C + i * 4), view_as<int>(vVelocity[i]), NumberType_Int32);
	}
	else
	{
		for (int i; i <= 2; i++)
			StoreToAddress(locomotion + view_as<Address>(0x60 + i * 4), view_as<int>(vVelocity[i]), NumberType_Int32);
	}
}

Address GetLocomotion( int entity )
{
    Address nextbot = GetNextBotPointer(entity);
    
    if ( !nextbot )
        return Address_Null;

    return GetLocomotionPointer(nextbot);
}

Address GetNextBotPointer( int entity )
{
    return SDKCall(g_hNextBotPointer, entity);
}

Address GetLocomotionPointer( Address nextbot )
{
    return SDKCall(g_hGetLocomotion, nextbot);
} 

public void OnActionCreated( BehaviorAction action, int actor, const char[] name )
{
	if (fl4d_tank_throw_witch == 0.0 || iThrowSILimit[4] == 0) return;

	if ( strcmp(name, "WitchIdle") == 0 )
	{
		action.OnUpdate = OnUpdate;
	}
}

public Action OnUpdate( BehaviorAction action, int actor, float interval, ActionResult result ) 
{
	if ( GetEntityFlags(actor) & FL_ONGROUND )
	{
		//action.OnUpdate = INVALID_FUNCTION;
		return Plugin_Continue;
	}

	return Plugin_Handled;
}