//+------------------------------------------------------------------+
//|                                                                  |
//| Gérer une stratégie en s'appuyant sur les données                |
//| communes                                                         |
//| (Le code est compatible MT4 et MT5)                              |
//|                                                                  |
//| - Détection d'une opportunité                                    |
//| - Affectation avec un ticket ouvert                              |
//| - Gestion des positions avec les détections                      |
//|                                                                  |
//+------------------------------------------------------------------+
//| Liste  des fonctions : (A compléter avec IA)


//////////////////////////////////////////////////////////
//                                                      //
//              C O N S T A N T E S                     //
//                                                      //
//////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////
//                                                      //
//                 I N C L U D E S                      //
//                                                      //
//////////////////////////////////////////////////////////
#include <BB_ADX_EXPERT/Datas.mqh>

//////////////////////////////////////////////////////////
//                                                      //
//                  C L A S S                           //
//                                                      //
//////////////////////////////////////////////////////////
class CStrategy
{
//==================================
//--- PRIVATE
//==================================    
private:
    // Données de la stratégie
    //------------------------
    CDatas        DATAS;
  
    // Données des indicateurs et ORB
    //--------------------------------
    int     m_HandleEMA20_M5;    // Handle EMA20 directionnelle
    int     m_HandleEMA50_M5;    // Handle EMA50 directionnelle
    int     m_HandleEMA20_M1;    // Handle EMA20 de management
    int     m_HandleEMA50_M1;    // Handle EMA50 de management
    int     m_HandleST_D;        // Handle SuperTrend directionnelle
    int     m_HandleST_M;        // Handle SuperTrend M1 pour détection plateaux
    int     m_HandleATR;         // Handle ATR (filtre range ORB)

    // ✅ SUPERTREND M1 - DÉTECTION DES PLATEAUX
    //-------------------------------------------
    STRUCT_ST_HISTORY m_STPlateau;         // État du tracking
    datetime          m_LastST_ReadTime;   // Anti-doublon M1

    // ✅ VARIABLES POUR VERROUILLAGE JOURNALIER
    //-------------------------------------------
    int             m_LockedDay;           // Jour verrouillé
    bool            m_PositionOpened;      // Flag position ouverte
    
    // Données
    //--------
    ENUM_TIMEFRAMES m_Period;
    bool            m_InitOk;

    // Fonctions
    //----------
    double   FindStop(const STRUCT_STRATEGY &i_datas);
    bool     CheckSuperTrend(ENUM_TREND &i_trend);
    bool     CheckEMA(ENUM_TREND &i_trend);
    void     ApplyBreakEven(const MqlTick &i_tick);
    bool     CheckTrendExitOnM1(void);
    bool     ClosePositionByTicket(const ulong i_ticket, const ENUM_POSITION_TYPE i_position_type);
    
    // ✅ SUPERTREND M1 - DÉTECTION DES PLATEAUX
    //-------------------------------------------
    void     InitSTPlateauTracking(const ENUM_TREND i_expected_direction);
    void     UpdateSTPlateauDetection(const MqlTick &i_tick);
    void     ResetSTPlateauTracking(void);
    bool     TryMoveSLToPlateauLevel(void);
    
    bool     IsSessionValid(void);
    bool     IsPositionOpenedToday(const MqlTick &i_tick);
    bool     HasPositionForSymbol(void);
    bool     HasPendingOrderForSymbol(void);

//==================================
//--- PUBLIC
//==================================    
public:
    // Fonctions
    //----------
    bool   Config(const string            i_strategy_name,
                  const ENUM_TIMEFRAMES   i_period,
                  const string            i_folder);

    bool   ConfigOk(void) { return(m_InitOk);  }

    void    End(void);

    // Infos venants de l'extérieur
    //-----------------------------
    void    SetTicket(const int i_detection, const int i_Ticket)     { DATAS.SetTicket(i_detection, i_Ticket); }

    // Gestion des données
    //--------------------
    int    GetPositionNb(void)                                      { return(DATAS.GetPositionNb()); }

    void    DeleteDetection(void)                                    { DATAS.DeleteDetection(); }

    void    CloseOfPositions(void)                                   { DATAS.CloseOfPositions(); }

    void    Detection(void);

    void    ManagePositions(void);                                   
};

//+------------------------------------------------------------------+
//| Config                                                           |
//| Initialise l'objet avec la création des indicateurs              |
//| INPUT:                                                           |
//|  Nom de la stratégie                                             |
//|  Période de la stratégie                                         |                                                                 
//| OUTPUT:                                                          |
//|  None                                                            |
//+------------------------------------------------------------------+
bool CStrategy::Config(const string            i_strategy_name,
                       const ENUM_TIMEFRAMES   i_period,
                       const string            i_folder)
{
    // Initialisation (également des indicateurs)
    //---------------    
    m_InitOk = false;
    m_Period = i_period;    

    // ✅ INITIALISER LE VERROUILLAGE
    //--------------------------------
    m_LockedDay = -1;
    m_PositionOpened = false;    
    
    // Configure la classe pour les données
    //-------------------------------------
    if (!DATAS.Config(i_strategy_name, i_period, i_folder)) return(false);

    // TODO : Initialisation des spécificités de la stratégie
    //-------------------------------------------------------

    // Initialisation
    //---------------
    m_HandleEMA20_M5  = INVALID_HANDLE;
    m_HandleEMA50_M5  = INVALID_HANDLE;
    m_HandleEMA20_M1  = INVALID_HANDLE;
    m_HandleEMA50_M1  = INVALID_HANDLE;
    m_HandleST_D      = INVALID_HANDLE; 
    m_HandleST_M      = INVALID_HANDLE;
    m_HandleATR       = INVALID_HANDLE;
    
    // ✅ SUPERTREND M1 INITIALIZATION
    //--------------------------------
    m_LastST_ReadTime = 0;
    ZeroMemory(m_STPlateau);
    m_STPlateau.active = false;      

    // Création des handles pour les indicateurs

    // EMA20 et EMA50 (M5)
    //--------------------
    m_HandleEMA20_M5  = iMA(Symbol(), PERIOD_M5, 20, 0, MODE_EMA, PRICE_CLOSE);
    if (m_HandleEMA20_M5 == INVALID_HANDLE)
    {
        LOG.ERROR(DATAS.GetStrategyName() + "Impossible d'initialiser l'indicateur EMA20 directionnelle !!!", __FUNCTION__);
        return(false);
    }
    m_HandleEMA50_M5 = iMA(Symbol(), PERIOD_M5, 50, 0, MODE_EMA, PRICE_CLOSE);
    if (m_HandleEMA50_M5 == INVALID_HANDLE)
    {
        LOG.ERROR(DATAS.GetStrategyName() + "Impossible d'initialiser l'indicateur EMA50 directionnelle !!!", __FUNCTION__);
        return(false);
    }

    // EMA20 et EMA50 (M1)
    //--------------------
    m_HandleEMA20_M1  = iMA(Symbol(), PERIOD_M1, 20, 0, MODE_EMA, PRICE_CLOSE);
    if (m_HandleEMA20_M1 == INVALID_HANDLE)
    {
        LOG.ERROR(DATAS.GetStrategyName() + "Impossible d'initialiser l'indicateur EMA20 de management !!!", __FUNCTION__);
        return(false);
    }
    m_HandleEMA50_M1 = iMA(Symbol(), PERIOD_M1, 50, 0, MODE_EMA, PRICE_CLOSE);
    if (m_HandleEMA50_M1 == INVALID_HANDLE)
    {
        LOG.ERROR(DATAS.GetStrategyName() + "Impossible d'initialiser l'indicateur EMA50 de management !!!", __FUNCTION__);
        return(false);
    }

    // ✅ SuperTrend v2 (Soltaniyan) - H1 (Directionnelle)
    // Paramètres : ATRPeriod, Multiplier, SourcePrice, TakeWicksIntoAccount
    // IMPORTANT : le fichier doit s'appeler "supertrend.ex5" (minuscules)
    //------------------------------------------------------------------------
    m_HandleST_D = iCustom(Symbol(), PERIOD_H1, "supertrend",
                           10,                      // ATRPeriod
                           3,                       // Multiplier
                           K_ST_Source,             // SourcePrice
                           true);                   // TakeWicksIntoAccount
    if (m_HandleST_D == INVALID_HANDLE)
    {
        LOG.ERROR(DATAS.GetStrategyName() + "Impossible d'initialiser l'indicateur SuperTrend directionnelle !!!", __FUNCTION__);
        return(false);
    }
    
    // ✅ SuperTrend v2 (Soltaniyan) - M1 (Détection plateaux)
    // Mêmes paramètres que H1
    //-----------------------------------------------------
    m_HandleST_M = iCustom(Symbol(), PERIOD_M1, "supertrend",
                           10,                      // ATRPeriod
                           3,                       // Multiplier
                           K_ST_Source,             // SourcePrice
                           true);                   // TakeWicksIntoAccount
    if (m_HandleST_M == INVALID_HANDLE)
    {
        LOG.ERROR(DATAS.GetStrategyName() + "Impossible d'initialiser l'indicateur SuperTrend M1 (plateaux) !!!", __FUNCTION__);
        return(false);
    }
    
    // ATR sur K_ORB_TF — filtre de range minimum
   //---------------------------------------------
   m_HandleATR = iATR(Symbol(), K_ORB_TF, 14);
   if (m_HandleATR == INVALID_HANDLE)
   {
       LOG.ERROR(DATAS.GetStrategyName() + "Impossible d'initialiser l'indicateur ATR !!!", __FUNCTION__);
       return(false);
   }
    
    // Fin de l'initialisation
    //------------------------
    m_InitOk = true;
    LOG.INFO(DATAS.GetStrategyName() + "Stratégie OPR initialisée", __FUNCTION__);
    return(true);
}

//+------------------------------------------------------------------+
//| End                                                              |
//| Ferme l'objet                                                    |
//| INPUT:                                                           |
//|  None                                                            |
//| OUTPUT:                                                          |
//|  None                                                            |
//+------------------------------------------------------------------+
void CStrategy::End(void)
{ 
    // Gère les données de la stratégie
    //---------------------------------
    DATAS.End(); 

    // TODO : Terminaison des spécificités de la stratégie
    //----------------------------------------------------

    if (m_HandleEMA20_M5 != INVALID_HANDLE) IndicatorRelease(m_HandleEMA20_M5);
    if (m_HandleEMA50_M5 != INVALID_HANDLE) IndicatorRelease(m_HandleEMA50_M5);
    if (m_HandleEMA20_M1 != INVALID_HANDLE) IndicatorRelease(m_HandleEMA20_M1);
    if (m_HandleEMA50_M1 != INVALID_HANDLE) IndicatorRelease(m_HandleEMA50_M1);
    if (m_HandleST_D     != INVALID_HANDLE) IndicatorRelease(m_HandleST_D);
    if (m_HandleST_M     != INVALID_HANDLE) IndicatorRelease(m_HandleST_M);
    if (m_HandleATR      != INVALID_HANDLE) IndicatorRelease(m_HandleATR);
    
    // ✅ RESET DES PLATEAUX À LA FERMETURE
    //------------------------------------
    ResetSTPlateauTracking();
}

//+--------------------------------------------------------------------+
//| Detection                                                          |
//| Analyse la stratégie en cas de nouvelle bougie                     |
//| INPUT:                                                             |
//|  None                                                              |
//| OUTPUT:                                                            |    
//|  None                                                              |
//+--------------------------------------------------------------------+
void CStrategy::Detection(void)
{ 
    // Variables locales
    //------------------
    STRUCT_STRATEGY          l_Datas;
    STRUCT_SYMBOL_CONFIG     l_Config = GetSymbolConfig(I_Symbol_Key);
    int                      l_NoDetection;
    bool                     l_DetectionOk;
    MqlTick                  l_TickData;
    string                   l_Header;
    
    // Initialise le traitement
    //-------------------------
    l_NoDetection = 0;
    l_DetectionOk = false;
    ZeroMemory(l_Datas);

    // Lit les dernières données du marché    
    //------------------------------------
    if (!SymbolInfoTick(Symbol(), l_TickData)) 
    {
        LOG.WARNING(DATAS.GetStrategyName() + "Lecture des données récentes du marché impossible", __FUNCTION__);
        return;
    }

    // Données et valeurs statiques pour qu'elles ne changent pas à chaque tick
    //-------------------------------------------------------------------------
    static datetime opr_start     = 0;
    static datetime opr_session   = 0;
    static datetime opr_end       = 0;
    static datetime opr_close     = 0;
    static datetime safe_read_time = 0;
    static double   opr_high      = 0.0;
    static double   opr_low       = 0.0;
    static int      opr_day       = -1;   
    MqlDateTime     dt;
    TimeCurrent(dt);    
    
    // On ne rentre ici qu'une seule fois par jour, à minuit (ou au premier tick du jour)
    //-----------------------------------------------------------------------------------
    if (dt.day != opr_day)
    {
        // Reset journalier
        //-----------------
        opr_high = 0.0;
        opr_low  = 0.0;
        opr_day  = dt.day;

        // Récupère les heures OPR dynamiques selon marché + DST
        //-------------------------------------------------------
        string today_str = TimeToString(TimeCurrent(), TIME_DATE);
        opr_start      = StringToTime(today_str + " 15:30");
        safe_read_time = opr_start + PeriodSeconds(K_ORB_TF);
        opr_session    = StringToTime(today_str + " 15:45");
        opr_end        = StringToTime(today_str + " 17:30");
        opr_close      = StringToTime(today_str + " 21:00");

        LOG.INFO("Nouvelle journée : OPR Start=" + TimeToString(opr_start) +
                 " | Session=" + TimeToString(opr_session) +
                 " | End="     + TimeToString(opr_end) +
                 " | Close="   + TimeToString(opr_close), __FUNCTION__);
    }

    // ✅ VÉRIFICATION SESSION (Jour + Mois)
    //--------------------------------------
    if (!IsSessionValid())
    {
        if (OrdersTotal() > 0)
        {
            LOG.INFO("Session invalide - Annulation des ordres en attente", __FUNCTION__);
            DATAS.CancelPendingOrder();
        }
        return;
    }       

    // ✅ VÉRIFICATION : Une position est-elle ouverte aujourd'hui ?
    //-------------------------------------------------------------
    if (IsPositionOpenedToday(l_TickData))
    {
        return;
    }

    // ✅ VÉRIFICATION ZONE NEWS
    //-------------------------
    if (!PARAM.OutsideSecurityZone())
    {
        if (HasPendingOrderForSymbol())
        {
           LOG.INFO("🔴 Zone NEWS - Annulation des ordres en attente", __FUNCTION__);
           DATAS.CancelPendingOrder();
        }
        return;
    }
        
    // Clôture forcée à OPR_Close
    //---------------------------
    if (TimeCurrent() >= opr_close)
    {
        if (PositionsTotal() > 0)
        {
            LOG.INFO("Clôture forcée des positions : OPR_Close", __FUNCTION__);
            DATAS.CloseOfPositions();            
        }
        DATAS.CancelPendingOrder();
        return;
    }

    // Logique de récupération de l'OPR high et low
    //----------------------------------------------
    if (TimeCurrent() >= safe_read_time)
    {
        if (opr_high == 0.0 || opr_low == 0.0)
        {
            double high_buf[], low_buf[];
            
            if (CopyHigh(Symbol(), K_ORB_TF, opr_start, 1, high_buf) == 1) 
            {
                opr_high = high_buf[0];
                LOG.INFO("OPR High enregistré: " + DoubleToString(opr_high, _Digits), __FUNCTION__);
            }
            else
            {
                LOG.WARNING("Impossible de lire OPR High", __FUNCTION__);
                return;
            }
            
            if (CopyLow(Symbol(), K_ORB_TF, opr_start, 1, low_buf) == 1) 
            {
                opr_low = low_buf[0];
                LOG.INFO("OPR Low enregistré: " + DoubleToString(opr_low, _Digits), __FUNCTION__);
            }
            else
            {
                LOG.WARNING("Impossible de lire OPR Low", __FUNCTION__);
                return;
            }                        
        }
    }
    else
    {
        return;  // Trop tôt
    }

    // Annulation des ordres non exécutés après OPR_End
    //--------------------------------------------------
    if (TimeCurrent() >= opr_end)
    {
        if (OrdersTotal() > 0)
        {
            LOG.INFO("OPR - End dépassé - Annulation ordres en attente", __FUNCTION__);
            DATAS.CancelPendingOrder();
        }
        return;
    }
    
    // Après le bloc qui lit opr_high et opr_low, avant "=== ANALYSE INDICATEURS ==="
   // Filtre ATR — range ORB trop petite
   //------------------------------------
   if (K_MinRange_ATR_Ratio > 0.0)
   {
       double atr_buf[];
       if (CopyBuffer(m_HandleATR, 0, 1, 1, atr_buf) == 1)
       {
           double range = opr_high - opr_low;
           double atr   = atr_buf[0];
           if (range < K_MinRange_ATR_Ratio * atr)
           {
               LOG.INFO("Range ORB trop petite (" + DoubleToString(range, _Digits) +
                        ") vs ATR×ratio ("        + DoubleToString(K_MinRange_ATR_Ratio * atr, _Digits) +
                        ") - Session ignorée", __FUNCTION__);
               return;
           }
       }
       else
       {
           LOG.WARNING("ATR indisponible - filtre range ignoré", __FUNCTION__);
       }
   }

    // === ANALYSE INDICATEURS ===
    //----------------------------
    ENUM_TREND st_trend  = eT_Unknown;
    ENUM_TREND ema_trend = eT_Unknown;
    
    if (!CheckSuperTrend(st_trend)) return;
    if (!CheckEMA(ema_trend)) return;

    // SI ORDRE EN ATTENTE, VÉRIFIER VALIDITÉ
    //----------------------------------------
    if (HasPendingOrderForSymbol())
    {
        if (st_trend != ema_trend)
        {
            LOG.INFO("Divergence ST/EMA - Annulation ordre", __FUNCTION__);
            DATAS.CancelPendingOrder();
        }
        return;
    }

    // Analyse OPR (seulement si pas de trade en cours)
    //-------------------------------------------------
    if (HasPositionForSymbol()) return; 

    // Convergence obligatoire ST + EMA
    //---------------------------------
    if (st_trend != ema_trend) return;

    // Offset anti fausse cassure (issu de la config actif)
    //------------------------------------------------------
    double offset = l_Config.offset_points;

    //--------------------
    // Contrôle si achat
    //--------------------
    if ((st_trend == eT_Bull) && (TimeCurrent() >= opr_session) && (TimeCurrent() < opr_end))
    {
        if (l_TickData.ask > opr_high + offset)
        {
            // Prix a déjà cassé → vérification slippage
            double l_Slippage = (l_TickData.ask - (opr_high + offset));
            if ((K_MaxSlippage_Points > 0.0) && (l_Slippage > K_MaxSlippage_Points))
            {
                LOG.INFO("🚫 Cassure trop lointaine (" + DoubleToString(l_Slippage, 0) +
                         " pts) > max autorisé (" + DoubleToString(K_MaxSlippage_Points, 0) +
                         " pts) - abandon", __FUNCTION__);
                return;
            }
            // Slippage acceptable → bascule ordre au marché
            l_NoDetection = DATAS.GetNewDetection();
            DATAS.GetData(l_NoDetection, l_Datas);
            l_Datas.Trend         = eT_Bull;
            l_Datas.Entry         = l_TickData.ask;
            l_Datas.StopLoss      = this.FindStop(l_Datas);
            l_Datas.TakeProfit    = 0.0;
            l_Datas.IsMarketOrder = true;
            l_DetectionOk         = true;
            LOG.WARNING("🚀 [INSTANT BREAKOUT] Bascule ordre au MARCHÉ | Slippage : " +
                        DoubleToString(l_Slippage, 0) + " pts", __FUNCTION__);
        }
        else
        {
            // Prix pas encore cassé → ordre stop classique
            l_NoDetection = DATAS.GetNewDetection();
            DATAS.GetData(l_NoDetection, l_Datas);
            l_Datas.Trend         = eT_Bull;
            l_Datas.Entry         = opr_high + offset;
            l_Datas.StopLoss      = this.FindStop(l_Datas);
            l_Datas.TakeProfit    = 0.0;
            l_Datas.IsMarketOrder = false;
            l_DetectionOk         = true;
            LOG.INFO("Ordre BUY STOP placé", __FUNCTION__);
        }
    }

    //--------------------
    // Contrôle si vente
    //--------------------    
    else if ((st_trend == eT_Bear) && (TimeCurrent() >= opr_session) && (TimeCurrent() < opr_end))
    {
        if (l_TickData.bid < opr_low - offset)
        {
            // Prix a déjà cassé → vérification slippage
            double l_Slippage = ((opr_low - offset) - l_TickData.bid);
            if ((K_MaxSlippage_Points > 0.0) && (l_Slippage > K_MaxSlippage_Points))
            {
                LOG.INFO("🚫 Cassure trop lointaine (" + DoubleToString(l_Slippage, 0) +
                         " pts) > max autorisé (" + DoubleToString(K_MaxSlippage_Points, 0) +
                         " pts) - abandon", __FUNCTION__);
                return;
            }
            // Slippage acceptable → bascule ordre au marché
            l_NoDetection = DATAS.GetNewDetection();
            DATAS.GetData(l_NoDetection, l_Datas);
            l_Datas.Trend         = eT_Bear;
            l_Datas.Entry         = l_TickData.bid;
            l_Datas.StopLoss      = this.FindStop(l_Datas);
            l_Datas.TakeProfit    = 0.0;
            l_Datas.IsMarketOrder = true;
            l_DetectionOk         = true;
            LOG.WARNING("🚀 [INSTANT BREAKOUT] Bascule ordre au MARCHÉ | Slippage : " +
                        DoubleToString(l_Slippage, 0) + " pts", __FUNCTION__);
        }
        else
        {
            // Prix pas encore cassé → ordre stop classique
            l_NoDetection = DATAS.GetNewDetection();
            DATAS.GetData(l_NoDetection, l_Datas);
            l_Datas.Trend         = eT_Bear;
            l_Datas.Entry         = opr_low - offset;
            l_Datas.StopLoss      = this.FindStop(l_Datas);
            l_Datas.TakeProfit    = 0.0;
            l_Datas.IsMarketOrder = false;
            l_DetectionOk         = true;
            LOG.INFO("Ordre SELL STOP placé", __FUNCTION__);
        }
    }

    // Gère les paramètres de la détection
    //--------------------------------------
    if (l_DetectionOk)
    {        
        l_Datas.Size = MONEY.CalculateLotSize(l_Datas);

        if (l_Datas.Size <= 0.0)
        {
            LOG.WARNING("Taille de lot invalide", __FUNCTION__);
            return;
        }

        l_Header = LOG.InfosLogOperation(DATAS.GetStrategyName(), l_Datas.No_detection, Symbol());
        LOG.INFO(l_Header +
                 " : Opportunité " + TrendToString(l_Datas.Trend) +
                 " : Taille = "    + DoubleToString(l_Datas.Size,       MONEY.GetDigitLot()) +
                 " , Entry = "     + DoubleToString(l_Datas.Entry,      Digits()) +
                 " , SL = "        + DoubleToString(l_Datas.StopLoss,   Digits()), __FUNCTION__);

        DATAS.SetData(l_NoDetection, l_Datas);

        // Invalidation de dernière minute
        //--------------------------------
        if (st_trend != ema_trend)
        {
            LOG.INFO(" Invalidation immédiate - ST != EMA", __FUNCTION__);
            return;
        }
        BROKER.SendOrder(DATAS.GetStrategyName(), l_Datas);
    }    
}

//+------------------------------------------------------------------+
//| ManagePositions                                                  |
//| Appelée à chaque tick depuis OnTick()                            |
//| Gère dans l'ordre :                                              |
//|  1. Zone NEWS  → annulation immédiate des ordres en attente      |
//|  2. BreakEven  → déplacement du SL si ratio atteint              |
//|  3. Divergence ST/EMA → annulation si conditions invalides       |
//| INPUT:                                                           |
//|  None                                                            |
//| OUTPUT:                                                          |
//|  None                                                            |
//+------------------------------------------------------------------+
void CStrategy::ManagePositions(void)
{
    // Variables locales
    //------------------
    MqlTick              l_Tick;
    STRUCT_SYMBOL_CONFIG l_Config    = GetSymbolConfig(I_Symbol_Key);
    ENUM_TREND           l_StTrend   = eT_Unknown;
    ENUM_TREND           l_EmaTrend  = eT_Unknown;

    // Lecture du tick courant
    //------------------------
    if (!SymbolInfoTick(Symbol(), l_Tick))
    {
        LOG.WARNING("ManagePositions : Impossible de lire le tick", __FUNCTION__);
        return;
    }
    
    // 1. ZONE NEWS : Priorité absolue
    //--------------------------------
    if (!PARAM.OutsideSecurityZone())
    {
        if (HasPendingOrderForSymbol())
        {
            LOG.INFO("🔴 Zone NEWS (tick) - Annulation immédiate des ordres", __FUNCTION__);
            DATAS.CancelPendingOrder();
        }

        // ✅ Détection plateaux ST M1 même en zone NEWS pour protéger les positions
        //----------------------------------------------------------------------
        if (l_Config.apply_be)
        {
            UpdateSTPlateauDetection(l_Tick);
        }
        return;
    }

    // 2. ✅ DÉTECTION PLATEAUX SUPERTREND M1
    //---------------------------------------
    if (l_Config.apply_be)
    {
        UpdateSTPlateauDetection(l_Tick);
    }

    // 3. SORTIE PAR CHANGEMENT DE TENDANCE (EMA PRIORITAIRE)
    //---------------------------------------------------------
    if (HasPositionForSymbol())
    {
        if (CheckTrendExitOnM1())
        {
            LOG.INFO("✅ Sortie déclenchée par EMA M1 / ST M1 - priorité EMA", __FUNCTION__);
            return;
        }
    }

    // 4. DIVERGENCE ST/EMA
    //---------------------
    if (HasPendingOrderForSymbol())
    {
        if (!CheckSuperTrend(l_StTrend) || !CheckEMA(l_EmaTrend) || (l_StTrend != l_EmaTrend))
        {
            LOG.INFO("⚡ Divergence ST/EMA (tick) - Annulation ordre", __FUNCTION__);
            DATAS.CancelPendingOrder();
        }
    }
}

//////////////////////////////////////////////////////////
//                                                      //
//                P R I V A T E                         //
//                                                      //
//////////////////////////////////////////////////////////

//+------------------------------------------------------------------+
//| IsPositionOpenedToday                                            |
//| Détecte si une position est ouverte, verrouille si oui           |
//| INPUT:                                                           |
//|  i_tick : tick courant                                           |
//| OUTPUT:                                                          |
//|  TRUE si position déjà ouverte aujourd'hui                       |
//+------------------------------------------------------------------+
bool CStrategy::IsPositionOpenedToday(const MqlTick &i_tick)
{
    MqlDateTime dt;
    TimeCurrent(dt);
    datetime day_start;
    int      l_Deals;
    
    // Reset à minuit
    //---------------
    if (dt.day != m_LockedDay)
    {
        m_LockedDay      = dt.day;
        m_PositionOpened = false;
        LOG.INFO("✅ Nouveau jour - Verrouillage réinitialisé", __FUNCTION__);
    }
    
    if (m_PositionOpened) return(true);
    
    // Détection via historique du jour
    //---------------------------------
    day_start = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " 00:00");
    
    if (!HistorySelect(day_start, TimeCurrent())) return(false);
    l_Deals = HistoryDealsTotal();
    for(int i = l_Deals - 1; i >= 0; i--)
    {
        ulong l_Ticket = HistoryDealGetTicket(i);

        if (HistoryDealGetString(l_Ticket, DEAL_SYMBOL)                != Symbol())              continue;
        if (HistoryDealGetInteger(l_Ticket, DEAL_MAGIC)                != (K_Magic + I_Robot_ID)) continue;
        if (HistoryDealGetInteger(l_Ticket, DEAL_ENTRY)                != DEAL_ENTRY_IN)          continue;

        LOG.INFO("🔒 Position ouverte trouvée dans l'historique d'aujourd'hui", __FUNCTION__);
        m_PositionOpened = true;
        
        // ✅ Initialiser le tracking des plateaux ST M1
        //---------------------------------------------
        ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(l_Ticket, DEAL_TYPE);
        ENUM_TREND trend = (deal_type == DEAL_BUY) ? eT_Bull : eT_Bear;
        InitSTPlateauTracking(trend);
        
        return(true);
    }

    // Détection via cassure du niveau d'entrée d'un ordre en attente
    //----------------------------------------------------------------
    for (int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong l_Ticket = OrderGetTicket(i);

        if (OrderGetString(ORDER_SYMBOL)  != Symbol())              continue;
        if (OrderGetInteger(ORDER_MAGIC)  != (K_Magic + I_Robot_ID)) continue;

        double entry = OrderGetDouble(ORDER_PRICE_OPEN);
        long   type  = OrderGetInteger(ORDER_TYPE);

        if (type == ORDER_TYPE_BUY_STOP  && i_tick.ask >= entry)
        {
            LOG.INFO("🔒 Cassure OPR détectée — verrouillage journée (BUY)", __FUNCTION__);
            m_PositionOpened = true;
            
            // ✅ Initialiser le tracking des plateaux ST M1
            //---------------------------------------------
            InitSTPlateauTracking(eT_Bull);
            
            return(true);
        }
        if (type == ORDER_TYPE_SELL_STOP && i_tick.bid <= entry)
        {
            LOG.INFO("🔒 Cassure OPR détectée — verrouillage journée (SELL)", __FUNCTION__);
            m_PositionOpened = true;
            
            // ✅ Initialiser le tracking des plateaux ST M1
            //---------------------------------------------
            InitSTPlateauTracking(eT_Bear);
            
            return(true);
        }    
    }

    // Détection via positions ouvertes actuellement
    //-----------------------------------------------
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong l_Ticket = PositionGetTicket(i);

        if (PositionGetString(POSITION_SYMBOL)  != Symbol())              continue;
        if (PositionGetInteger(POSITION_MAGIC)  != (K_Magic + I_Robot_ID)) continue;

        LOG.INFO("🔒 Position détectée (ouverte actuellement)", __FUNCTION__);
        m_PositionOpened = true;
        
        // ✅ Initialiser le tracking des plateaux ST M1
        //---------------------------------------------
        ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        ENUM_TREND trend = (pos_type == POSITION_TYPE_BUY) ? eT_Bull : eT_Bear;
        InitSTPlateauTracking(trend);
        
        return(true);
    }
    
    return(false);
}

//+------------------------------------------------------------------+
//| ✅ InitSTPlateauTracking                                         |
//| Initialise le suivi des plateaux SuperTrend M1                   |
//| INPUT:                                                           |
//|  i_expected_direction : Direction attendue (eT_Bull ou eT_Bear) |
//| OUTPUT:                                                          |
//|  None                                                            |
//+------------------------------------------------------------------+
void CStrategy::InitSTPlateauTracking(const ENUM_TREND i_expected_direction)
{
    // Réinitialiser l'état du suivi
    //------------------------------
    ZeroMemory(m_STPlateau);
    
    // Configuration
    //--------------
    m_STPlateau.expected_direction         = i_expected_direction;
    m_STPlateau.active                     = true;
    m_STPlateau.current_candidate.valid    = false;
    m_STPlateau.current_candidate.level    = 0;
    m_STPlateau.current_candidate.count    = 0;
    m_STPlateau.last_confirmed.valid       = false;
    m_STPlateau.previous_confirmed.valid   = false;
    m_LastST_ReadTime                      = 0;
    
    // Log
    //-----
    string direction = (i_expected_direction == eT_Bull) ? "📈 LONG (UP)" : "📉 SHORT (DOWN)";
    LOG.INFO("[ST PLATEAU] Suivi initialisé | Direction: " + direction, __FUNCTION__);
}

//+------------------------------------------------------------------+
//| ✅ UpdateSTPlateauDetection                                      |
//| Met à jour la détection des plateaux SuperTrend M1               |
//| Appelée à chaque tick si apply_be est actif                      |
//| INPUT:                                                           |
//|  i_tick : Le tick courant                                        |
//| OUTPUT:                                                          |
//|  None                                                            |
//+------------------------------------------------------------------+
void CStrategy::UpdateSTPlateauDetection(const MqlTick &i_tick)
{
    // Vérifier que le suivi est actif
    //--------------------------------
    if (!m_STPlateau.active) return;
    
    // Vérifier qu'il y a au moins une position ouverte
    //--------------------------------------------------
    if (PositionsTotal() == 0) 
    {
        ResetSTPlateauTracking();
        return;
    }
    
    // Anti-doublon : éviter traiter plusieurs fois la même barre M1
    //---------------------------------------------------------------
    datetime current_m1_time = iTime(Symbol(), PERIOD_M1, 0);
    double   st_value_m1     = 0.0;
    double   st_direction_m1 = 0.0;
    
    // Lire le SuperTrend M1 (buffer 0 = valeur, buffer 2 = direction)
    //---------------------------------------------------------------
    double buffer_value_temp[1];
    double buffer_dir_temp[1];
    
    if (CopyBuffer(m_HandleST_M1, 0, 0, 1, buffer_value_temp) != 1) return;
    st_value_m1 = buffer_value_temp[0];
    
    if (CopyBuffer(m_HandleST_M1, 2, 0, 1, buffer_dir_temp) != 1) return;
    st_direction_m1 = buffer_dir_temp[0];
    
    // Ignorer les valeurs invalides (ST pas encore prêt)
    //---------------------------------------------------
    if (st_value_m1 <= 0) return;
    if (st_direction_m1 == 0) return;  // Direction neutre
    
    // Ignorer les ticks qui ne matchent pas la direction attendue
    //------------------------------------------------------------
    ENUM_TREND st_detected_trend = (st_direction_m1 > 0.0) ? eT_Bull : eT_Bear;
    if (st_detected_trend != m_STPlateau.expected_direction) 
    {
        // C'est du bruit - ignorer
        return;
    }
    
    // Anti-doublon : vérifier si c'est la même barre M1
    //---------------------------------------------------
    if (m_LastST_ReadTime == current_m1_time && m_STPlateau.current_candidate.last_st_value == st_value_m1)
    {
        // Même barre M1 déjà traitée - ignorer
        return;
    }
    
    m_LastST_ReadTime = current_m1_time;
    m_STPlateau.current_candidate.last_st_value = st_value_m1;
    
    // Calculer E(ST) = partie entière = FLOOR(value)
    //-----------------------------------------------
    int current_level = (int)MathFloor(st_value_m1);
    
    // Première détection ou changement de niveau?
    //-------------------------------------------
    if (m_STPlateau.current_candidate.level == 0)
    {
        // Premier candidat
        //---------------
        m_STPlateau.current_candidate.level      = current_level;
        m_STPlateau.current_candidate.first_value = st_value_m1;
        m_STPlateau.current_candidate.count      = 1;
        m_STPlateau.current_candidate.valid      = false;
        
        LOG.INFO("[ST PLATEAU] Nouveau candidat | Level=" + IntegerToString(current_level) + 
                 " FirstValue=" + DoubleToString(st_value_m1, _Digits), __FUNCTION__);
    }
    else if (current_level == m_STPlateau.current_candidate.level)
    {
        // Même niveau - incrémenter le compteur
        //-----------------------------------------
        m_STPlateau.current_candidate.count++;
        
        LOG.INFO("[ST PLATEAU] Occurrence " + IntegerToString(m_STPlateau.current_candidate.count) + 
                 " | Level=" + IntegerToString(current_level), __FUNCTION__);
        
        // Plateau confirmé?
        //-----------------
        if (m_STPlateau.current_candidate.count >= (int)I_ST_Plateau_MinCount)
        {
            // ✅ PLATEAU CONFIRMÉ
            //-------------------
            m_STPlateau.current_candidate.valid = true;
            LOG.INFO("[ST PLATEAU] ✅ CONFIRMÉ | Level=" + IntegerToString(current_level) + 
                     " Count=" + IntegerToString(m_STPlateau.current_candidate.count), __FUNCTION__);
            
            // Tenter de déplacer le SL au niveau du plateau confirmé précédent
            //------------------------------------------------------------------
            if (TryMoveSLToPlateauLevel())
            {
                LOG.INFO("[ST PLATEAU] SL déplacé avec succès", __FUNCTION__);
            }
            
            // Rotation des plateaux
            //---------------------
            m_STPlateau.previous_confirmed = m_STPlateau.last_confirmed;
            m_STPlateau.last_confirmed = m_STPlateau.current_candidate;
            
            // Réinitialiser le candidat courant
            //----------------------------------
            ZeroMemory(m_STPlateau.current_candidate);
            m_STPlateau.current_candidate.valid = false;
            m_STPlateau.current_candidate.level = 0;
            m_STPlateau.current_candidate.count = 0;
        }
    }
    else
    {
        // Changement de niveau - réinitialiser avec le nouveau
        //-------------------------------------------------------
        LOG.INFO("[ST PLATEAU] Changement de niveau | OldLevel=" + IntegerToString(m_STPlateau.current_candidate.level) + 
                 " NewLevel=" + IntegerToString(current_level), __FUNCTION__);
        
        m_STPlateau.current_candidate.level       = current_level;
        m_STPlateau.current_candidate.first_value = st_value_m1;
        m_STPlateau.current_candidate.count       = 1;
        m_STPlateau.current_candidate.valid       = false;
    }
}

//+------------------------------------------------------------------+
//| ✅ ResetSTPlateauTracking                                        |
//| Réinitialise le suivi des plateaux                               |
//| Appelée quand une position se ferme                              |
//| INPUT:                                                           |
//|  None                                                            |
//| OUTPUT:                                                          |
//|  None                                                            |
//+------------------------------------------------------------------+
void CStrategy::ResetSTPlateauTracking(void)
{
    if (m_STPlateau.active)
    {
        LOG.INFO("[ST PLATEAU] Suivi réinitialisé", __FUNCTION__);
    }
    
    ZeroMemory(m_STPlateau);
    m_STPlateau.active = false;
    m_LastST_ReadTime = 0;
}

//+------------------------------------------------------------------+
//| ✅ TryMoveSLToPlateauLevel                                       |
//| Essaie de déplacer le SL vers le niveau du plateau précédent     |
//| (previous_confirmed.first_value)                                 |
//| INPUT:                                                           |
//|  None                                                            |
//| OUTPUT:                                                          |
//|  true si le SL a été déplacé avec succès                         |
//+------------------------------------------------------------------+
bool CStrategy::TryMoveSLToPlateauLevel(void)
{
    // Vérifier qu'il y a un plateau précédent confirmé
    //--------------------------------------------------
    if (!m_STPlateau.previous_confirmed.valid)
    {
        LOG.WARNING("[ST PLATEAU] Pas de plateau précédent pour déplacer le SL", __FUNCTION__);
        return(false);
    }
    
    // Récupérer la position ouverte
    //------------------------------
    ulong ticket = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong pos_ticket = PositionGetTicket(i);
        if (PositionGetString(POSITION_SYMBOL)  == Symbol() && 
            PositionGetInteger(POSITION_MAGIC)  == (K_Magic + I_Robot_ID))
        {
            ticket = pos_ticket;
            break;
        }
    }
    
    if (ticket == 0)
    {
        LOG.WARNING("[ST PLATEAU] Position non trouvée", __FUNCTION__);
        return(false);
    }
    
    // Récupérer les paramètres de la position
    //----------------------------------------
    if (!PositionSelectByTicket(ticket))
    {
        LOG.WARNING("[ST PLATEAU] Impossible de sélectionner la position", __FUNCTION__);
        return(false);
    }
    
    double current_sl = PositionGetDouble(POSITION_SL);
    ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double new_sl = m_STPlateau.previous_confirmed.first_value;
    int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    
    // Normaliser les prix
    //-------------------
    current_sl = NormalizeDouble(current_sl, digits);
    new_sl = NormalizeDouble(new_sl, digits);
    
    // Vérifier que le nouveau SL est plus favorable que l'actuel
    //-----------------------------------------------------------
    if (pos_type == POSITION_TYPE_BUY)
    {
        // Pour un BUY : nouveau SL doit être plus haut (plus favorable)
        if (new_sl <= current_sl)
        {
            LOG.INFO("[ST PLATEAU] Nouveau SL non favorable pour BUY | Current=" + 
                     DoubleToString(current_sl, _Digits) + " New=" + DoubleToString(new_sl, _Digits), __FUNCTION__);
            return(false);
        }
    }
    else if (pos_type == POSITION_TYPE_SELL)
    {
        // Pour un SELL : nouveau SL doit être plus bas (plus favorable)
        if (new_sl >= current_sl)
        {
            LOG.INFO("[ST PLATEAU] Nouveau SL non favorable pour SELL | Current=" + 
                     DoubleToString(current_sl, _Digits) + " New=" + DoubleToString(new_sl, _Digits), __FUNCTION__);
            return(false);
        }
    }
    
    // Construire la requête de modification
    //--------------------------------------
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_SLTP;
    request.symbol = Symbol();
    request.sl = new_sl;
    request.tp = PositionGetDouble(POSITION_TP);
    request.position = ticket;
    request.type_filling = ORDER_FILLING_FOK;
    
    // Envoyer la requête
    //------------------
    if (!OrderSend(request, result))
    {
        LOG.WARNING("[ST PLATEAU] Erreur OrderSend | Code=" + IntegerToString(result.retcode) + 
                    " Message=" + result.comment, __FUNCTION__);
        return(false);
    }
    
    if (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
    {
        LOG.INFO("[ST PLATEAU] ✅ SL déplacé | Ancien=" + DoubleToString(current_sl, _Digits) + 
                 " Nouveau=" + DoubleToString(new_sl, _Digits) + " Level=" + 
                 IntegerToString(m_STPlateau.previous_confirmed.level), __FUNCTION__);
        return(true);
    }
    else
    {
        LOG.WARNING("[ST PLATEAU] OrderSend rejetée | Retcode=" + IntegerToString(result.retcode), __FUNCTION__);
        return(false);
    }
}

//+------------------------------------------------------------------+
//| CheckTrendExitOnM1                                               |
//| Sortie si la tendance EMA M1 change, ST M1 sert d'alerte/confirm. |
//| L'EMA a la priorité si ST et EMA ne parlent pas le même langage. |
//| INPUT:                                                           |
//|  None                                                            |
//| OUTPUT:                                                          |
//|  TRUE si au moins une position a été fermée                     |
//+------------------------------------------------------------------+
bool CStrategy::CheckTrendExitOnM1(void)
{
    double ema20[];
    double ema50[];
    double st_dir[];

    if (CopyBuffer(m_HandleEMA20_M1, 0, 1, 1, ema20) != 1)
    {
        LOG.WARNING(DATAS.GetStrategyName() + "EMA20 M1 indisponible pour la sortie", __FUNCTION__);
        return(false);
    }
    if (CopyBuffer(m_HandleEMA50_M1, 0, 1, 1, ema50) != 1)
    {
        LOG.WARNING(DATAS.GetStrategyName() + "EMA50 M1 indisponible pour la sortie", __FUNCTION__);
        return(false);
    }
    if (CopyBuffer(m_HandleST_M, 2, 1, 1, st_dir) != 1)
    {
        LOG.WARNING(DATAS.GetStrategyName() + "SuperTrend M1 indisponible pour la sortie", __FUNCTION__);
        return(false);
    }

    ArraySetAsSeries(ema20, true);
    ArraySetAsSeries(ema50, true);
    ArraySetAsSeries(st_dir, true);

    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong l_Ticket = PositionGetTicket(i);
        if (PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
        if (PositionGetInteger(POSITION_MAGIC) != (K_Magic + I_Robot_ID)) continue;

        ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        bool ema_exit = false;
        bool st_flip  = false;

        if (pos_type == POSITION_TYPE_BUY)
        {
            ema_exit = (ema20[0] < ema50[0]);
            st_flip  = (st_dir[0] < 0.0);
        }
        else if (pos_type == POSITION_TYPE_SELL)
        {
            ema_exit = (ema20[0] > ema50[0]);
            st_flip  = (st_dir[0] > 0.0);
        }
        else
        {
            continue;
        }

        if (!ema_exit) continue;

        if (st_flip)
        {
            LOG.INFO("⚠️ Changement de tendance confirmé par ST M1 + EMA M1 | Ticket=" +
                     IntegerToString(l_Ticket) + " | EMA20=" + DoubleToString(ema20[0], _Digits) +
                     " | EMA50=" + DoubleToString(ema50[0], _Digits), __FUNCTION__);
        }
        else
        {
            LOG.INFO("⚠️ EMA M1 décide la sortie (ST ne confirme pas) | Ticket=" +
                     IntegerToString(l_Ticket) + " | EMA20=" + DoubleToString(ema20[0], _Digits) +
                     " | EMA50=" + DoubleToString(ema50[0], _Digits), __FUNCTION__);
        }

        if (ClosePositionByTicket(l_Ticket, pos_type))
        {
            return(true);
        }
    }

    return(false);
}

//+------------------------------------------------------------------+
//| ClosePositionByTicket                                            |
//| Fermeture d'une position spécifique sur signal EMA/ST             |
//| INPUT:                                                           |
//|  i_ticket : ticket de position                                    |
//|  i_position_type : BUY ou SELL                                    |
//| OUTPUT:                                                          |
//|  TRUE si la fermeture a été envoyée avec succès                  |
//+------------------------------------------------------------------+
bool CStrategy::ClosePositionByTicket(const ulong i_ticket, const ENUM_POSITION_TYPE i_position_type)
{
    if (!PositionSelectByTicket(i_ticket))
    {
        LOG.WARNING("Position introuvable pour fermeture | Ticket=" + IntegerToString(i_ticket), __FUNCTION__);
        return(false);
    }

    MqlTradeRequest l_Request;
    MqlTradeResult  l_Result;
    ZeroMemory(l_Request);
    ZeroMemory(l_Result);

    l_Request.action   = TRADE_ACTION_DEAL;
    l_Request.position = i_ticket;
    l_Request.symbol   = Symbol();
    l_Request.volume   = PositionGetDouble(POSITION_VOLUME);
    l_Request.price    = (i_position_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_BID) : SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    l_Request.type     = (i_position_type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    l_Request.magic    = K_Magic + I_Robot_ID;
    l_Request.deviation = 20;

    ResetLastError();
    if (!OrderSend(l_Request, l_Result))
    {
        LOG.ERROR("OrderSend fermeture échec | Ticket=" + IntegerToString(i_ticket) +
                  " | Error=" + IntegerToString(GetLastError()), __FUNCTION__);
        return(false);
    }

    if (l_Result.retcode == TRADE_RETCODE_DONE ||
        l_Result.retcode == TRADE_RETCODE_PLACED ||
        l_Result.retcode == TRADE_RETCODE_DONE_PARTIAL)
    {
        LOG.INFO("✅ Position fermée par EMA M1 | Ticket=" + IntegerToString(i_ticket) +
                 " | Type=" + EnumToString(i_position_type) +
                 " | Prix=" + DoubleToString(l_Request.price, _Digits), __FUNCTION__);
        return(true);
    }

    LOG.WARNING("Fermeture refusée | Ticket=" + IntegerToString(i_ticket) +
                " | Retcode=" + IntegerToString(l_Result.retcode) +
                " | Comment=" + l_Result.comment, __FUNCTION__);
    return(false);
}

//+------------------------------------------------------------------+
//| IsSessionValid                                                   |
//| Vérifie si le jour et le mois sont valides pour trader           |
//| La configuration est lue depuis GetSymbolConfig()                |
//| INPUT:                                                           |
//|  None                                                            |
//| OUTPUT:                                                          |
//|  TRUE si le jour et le mois sont valides                         |
//+------------------------------------------------------------------+
bool CStrategy::IsSessionValid(void)
{
    STRUCT_SYMBOL_CONFIG l_Config = GetSymbolConfig(I_Symbol_Key);
    MqlDateTime          l_Dt;
    TimeCurrent(l_Dt);

    // Vérification des mois exclus
    //------------------------------
    for (int i = 0; i < l_Config.nb_excl_months; i++)
    {
        if (l_Dt.mon == l_Config.excluded_months[i]) return(false);
    }

    // Vérification des jours exclus
    //-------------------------------
    for (int i = 0; i < l_Config.nb_excl_days; i++)
    {
        if (l_Dt.day_of_week == l_Config.excluded_days[i]) return(false);
    }

    return(true);
}

//+------------------------------------------------------------------+
//| HasPositionForSymbol                                             |
//| Détecte si une position est ouverte pour l'actif                 |
//| INPUT:                                                           |
//|  None                                                            |
//| OUTPUT:                                                          |
//|  TRUE si une position est ouverte                                |
//+------------------------------------------------------------------+
bool CStrategy::HasPositionForSymbol(void)
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong l_Ticket = PositionGetTicket(i);
        if (PositionGetString(POSITION_SYMBOL)  != Symbol())              continue;
        if (PositionGetInteger(POSITION_MAGIC)  != (K_Magic + I_Robot_ID)) continue;
        return(true);
    }
    return(false);
}

//+------------------------------------------------------------------+
//| HasPendingOrderForSymbol                                         |
//| Détecte si un ordre est en attente pour l'actif                  |
//| INPUT:                                                           |
//|  None                                                            |
//| OUTPUT:                                                          |
//|  TRUE si un ordre est en attente                                 |
//+------------------------------------------------------------------+
bool CStrategy::HasPendingOrderForSymbol(void)
{
    for (int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong l_Ticket = OrderGetTicket(i);
        if (OrderGetString(ORDER_SYMBOL)  != Symbol())              continue;
        if (OrderGetInteger(ORDER_MAGIC)  != (K_Magic + I_Robot_ID)) continue;
        return(true);
    }
    return(false);
}

//+------------------------------------------------------------------+
//| FindStop                                                         |
//| Calcule le stop loss (milieu du range OPR)                       |
//| INPUT:                                                           |
//|  i_datas : données de la détection                               |
//| OUTPUT:                                                          |
//|  Prix du stop loss (milieu du range OPR)                         |
//+------------------------------------------------------------------+
double CStrategy::FindStop(const STRUCT_STRATEGY &i_datas)
{
    static datetime opr_start      = 0;
    static datetime safe_read_time = 0;
    static double   opr_high       = 0.0;
    static double   opr_low        = 0.0;
    static int      opr_day        = -1;

    MqlDateTime dt;
    TimeCurrent(dt);

    if (dt.day != opr_day)
    {
        opr_high = 0.0;
        opr_low  = 0.0;
        opr_day  = dt.day;

        // Récupère uniquement start_h/m (FindStop n'a besoin que de opr_start)
        //-----------------------------------------------------------------------
        string today_str = TimeToString(TimeCurrent(), TIME_DATE);
        opr_start        = StringToTime(today_str + " 15:30");
        safe_read_time   = opr_start + PeriodSeconds(K_ORB_TF);

        LOG.INFO("FindStop | OPR Start=" + TimeToString(opr_start), __FUNCTION__);
    }

    if (TimeCurrent() >= safe_read_time)
    {
        if (opr_high == 0.0 || opr_low == 0.0)
        {
            double high_buf[], low_buf[];

            if (CopyHigh(Symbol(), K_ORB_TF, opr_start, 1, high_buf) == 1) 
            {
                opr_high = high_buf[0];
                LOG.INFO("OPR High enregistré: " + DoubleToString(opr_high, _Digits), __FUNCTION__);
            }
            else
            {
                LOG.WARNING("Impossible de lire OPR High", __FUNCTION__);
            }
            
            if (CopyLow(Symbol(), K_ORB_TF, opr_start, 1, low_buf) == 1) 
            {
                opr_low = low_buf[0];
                LOG.INFO("OPR Low enregistré: " + DoubleToString(opr_low, _Digits), __FUNCTION__);
            }
            else
            {
                LOG.WARNING("Impossible de lire OPR Low", __FUNCTION__);
            }                        
        }
    }

    // Retourne le milieu de range comme stop loss
    //---------------------------------------------
    double range = opr_high - opr_low;

   if (i_datas.Trend == eT_Bull)
   {
       switch(K_SL_Type)
       {
           case eSL_Mid:           return((opr_high + opr_low) / 2.0);
           case eSL_LowHigh:       return(opr_low);
           case eSL_LowHighBuffer: return(opr_low - range * K_SL_Buffer_Ratio);
       }
   }
   else
   {
       switch(K_SL_Type)
       {
           case eSL_Mid:           return((opr_high + opr_low) / 2.0);
           case eSL_LowHigh:       return(opr_high);
           case eSL_LowHighBuffer: return(opr_high + range * K_SL_Buffer_Ratio);
       }
   }
   return((opr_high + opr_low) / 2.0); // fallback
}

//+------------------------------------------------------------------+
//| CheckSuperTrend                                                  |
//| Vérifie direction ST (bougie clôturée)                           |
//| INPUT:                                                           |
//|  i_trend : tendance détectée (par référence)                     |
//| OUTPUT:                                                          |
//|  TRUE si on a une tendance de la ST                              |
//+------------------------------------------------------------------+
bool CStrategy::CheckSuperTrend(ENUM_TREND &i_trend)
{
    double st_direction[];

    if (CopyBuffer(m_HandleST, 2, 1, 1, st_direction) != 1)
    {
        LOG.WARNING(DATAS.GetStrategyName() + "SuperTrend indisponible", __FUNCTION__);
        return(false);
    }    
    ArraySetAsSeries(st_direction, true);

    if      (st_direction[0] > 0.0) i_trend = eT_Bull;
    else if (st_direction[0] < 0.0) i_trend = eT_Bear;
    else                            return(false);

    return(true);
}

//+------------------------------------------------------------------+
//| CheckEMA                                                         |
//| Vérifie EMA20 vs EMA50 (bougie clôturée)                         |
//| INPUT:                                                           |
//|  i_trend : tendance détectée (par référence)                     |
//| OUTPUT:                                                          |
//|  TRUE si on a une tendance sur les EMAs                          |
//+------------------------------------------------------------------+
bool CStrategy::CheckEMA(ENUM_TREND &i_trend)
{
    double ema20[];
    double ema50[];

    if (CopyBuffer(m_HandleEMA20, 0, 1, 1, ema20) != 1)
    {
        LOG.WARNING(DATAS.GetStrategyName() + "EMA20 indisponible", __FUNCTION__);
        return(false);
    }    
    if (CopyBuffer(m_HandleEMA50, 0, 1, 1, ema50) != 1)
    {
        LOG.WARNING(DATAS.GetStrategyName() + "EMA50 indisponible", __FUNCTION__);
        return(false);
    }    
    ArraySetAsSeries(ema20, true);
    ArraySetAsSeries(ema50, true);

    if      (ema20[0] > ema50[0]) i_trend = eT_Bull;
    else if (ema20[0] < ema50[0]) i_trend = eT_Bear;
    else                          return(false);

    return(true);
}

//+------------------------------------------------------------------+
//| ApplyBreakEven                                                   |
//| Déplace le SL au niveau du prix d'entrée + buffer                |
//| dès que le ratio cible est atteint                               |
//| INPUT:                                                           |
//|  i_tick : tick courant (pour le spread)                          |
//| OUTPUT:                                                          |
//|  None                                                            |
//+------------------------------------------------------------------+
void CStrategy::ApplyBreakEven(const MqlTick &i_tick)
{
    // Variables locales
    //------------------
    STRUCT_SYMBOL_CONFIG l_Config = GetSymbolConfig(I_Symbol_Key);
    MqlTradeRequest      l_Request;
    MqlTradeResult       l_Result;
    ulong    l_Ticket;
    ulong    l_Magic;
    string   l_Symbol;
    double   l_OpenPrice;
    double   l_CurrentSL;
    double   l_CurrentTP;
    double   l_CurrentPrice;
    double   l_CurrentProfit;
    double   l_Ratio;
    double   l_InitialRisk;
    double   l_NewSL;
    double   l_Point;
    double   l_Spread;
    double   l_Buffer;
    bool     l_Update;
    long     l_Type;
    int      l_Digits;     

    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        l_Ticket = PositionGetTicket(i);
        l_Symbol = PositionGetString(POSITION_SYMBOL);
        
        if (l_Symbol != Symbol())                                          continue;
        if (PositionGetInteger(POSITION_MAGIC) != (K_Magic + I_Robot_ID)) continue;

        l_OpenPrice    = PositionGetDouble(POSITION_PRICE_OPEN);
        l_CurrentSL    = PositionGetDouble(POSITION_SL);
        l_CurrentTP    = PositionGetDouble(POSITION_TP);
        l_CurrentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
        l_Type         = PositionGetInteger(POSITION_TYPE);
        l_Magic        = PositionGetInteger(POSITION_MAGIC);
        l_Digits       = (int)SymbolInfoInteger(l_Symbol, SYMBOL_DIGITS);
        l_Point        = SymbolInfoDouble(l_Symbol, SYMBOL_POINT);
        
        // ✅ FIX BE INFINI : SL déjà au-delà du prix d'entrée → BE déjà appliqué
        //------------------------------------------------------------------------
        if (l_Type == POSITION_TYPE_BUY  && l_CurrentSL >= l_OpenPrice)           continue;
        if (l_Type == POSITION_TYPE_SELL && l_CurrentSL <= l_OpenPrice
                                         && l_CurrentSL >  0.0)                   continue;

        l_InitialRisk = MathAbs(l_OpenPrice - l_CurrentSL);
        if (l_InitialRisk == 0) continue;

        if (l_Type == POSITION_TYPE_BUY)
            l_CurrentProfit = l_CurrentPrice - l_OpenPrice;
        else
            l_CurrentProfit = l_OpenPrice - l_CurrentPrice;
        
        l_Ratio = l_CurrentProfit / l_InitialRisk;

        // Ratio cible non atteint → pas encore de BE
        //--------------------------------------------
        double be_ratio = (K_BE_Override > 0) ? K_BE_Override : l_Config.breakeven_r;
        if (l_Ratio < be_ratio) continue;
        
        l_Update = false;
        l_Spread = i_tick.ask - i_tick.bid;
        l_Buffer = l_Config.buffer_be * l_Point;
                    
        if (l_Type == POSITION_TYPE_BUY)
        {
            l_NewSL = l_OpenPrice + l_Spread + l_Buffer;
            if (l_CurrentSL < l_NewSL) l_Update = true;
        }
        else
        {
            l_NewSL = l_OpenPrice - l_Spread - l_Buffer;
            if (l_CurrentSL > l_NewSL) l_Update = true;
        }
         
        LOG.INFO("🔍 BE check | " + l_Symbol +
                 " | Ratio : "     + DoubleToString(l_Ratio,      2) + "R" +
                 " | Spread : "    + DoubleToString(l_Spread,      l_Digits) +
                 " | Buffer : "    + DoubleToString(l_Buffer,      l_Digits) +
                 " | NewSL : "     + DoubleToString(l_NewSL,       l_Digits) +
                 " | CurrentSL : " + DoubleToString(l_CurrentSL,   l_Digits) +
                 " | Update : "    + (l_Update ? "OUI" : "NON"), __FUNCTION__);         

        if (!l_Update) continue;
        
        // Éviter race condition, ordre BE arrive après TP durant une news volatile
        //-------------------------------------------------------------------------
        if (!PositionSelectByTicket(l_Ticket))
        {
            LOG.INFO("✅ Position #" + IntegerToString(l_Ticket) +
                     " déjà fermée (TP/SL atteint) - BE ignoré", __FUNCTION__);
            continue;
        }        

        ZeroMemory(l_Request);
        ZeroMemory(l_Result);

        l_Request.action   = TRADE_ACTION_SLTP;
        l_Request.position = l_Ticket;
        l_Request.symbol   = l_Symbol;
        l_Request.sl       = NormalizeDouble(l_NewSL, l_Digits);
        l_Request.tp       = l_CurrentTP;
        l_Request.magic    = l_Magic;

        ResetLastError();
        if (!OrderSend(l_Request, l_Result))
        {
            LOG.ERROR("OrderSend BE échec : " + ErrorToString(GetLastError()), __FUNCTION__);
        }
        else
        {
            if (l_Result.retcode == TRADE_RETCODE_DONE         ||
                l_Result.retcode == TRADE_RETCODE_PLACED        ||
                l_Result.retcode == TRADE_RETCODE_DONE_PARTIAL)
            {
                LOG.INFO("✅ BE appliqué #" + IntegerToString(l_Ticket) +
                         " | Ratio : "       + DoubleToString(l_Ratio,  2) + "R" +
                         " | Nouveau SL : "  + DoubleToString(l_NewSL,  l_Digits), __FUNCTION__);
            }
            else
            {
                LOG.WARNING("⚠️ BE refusé #"  + IntegerToString(l_Ticket) +
                            " | Retcode : "   + IntegerToString(l_Result.retcode) +
                            " | "             + l_Result.comment, __FUNCTION__);
            }
        }
    }
}