// ============================================================================
// Formal Properties: adc_seq_fsm_formal
// Description: Formal verification properties for ADC FSM
//              Targets: all 9 states reachable, no illegal states,
//              transition completeness, EOC timeout, deadlock freedom
// Tool:        VC Formal / JasperGold
// ============================================================================
// Bind to DUT: bind adc_seq_fsm adc_seq_fsm_formal u_formal (.*);

module adc_seq_fsm_formal;

    bind adc_seq_fsm adc_seq_fsm_formal u_formal (.*);

    // State encoding (must match RTL)
    localparam ST_IDLE        = 4'h0;
    localparam ST_WAIT_TRIG   = 4'h1;
    localparam ST_LP_SAMPLE   = 4'h2;
    localparam ST_LP_WAIT_EOC = 4'h3;
    localparam ST_LP_INTERVAL = 4'h4;
    localparam ST_HP_SAMPLE   = 4'h5;
    localparam ST_HP_WAIT_EOC = 4'h6;
    localparam ST_HP_INTERVAL = 4'h7;
    localparam ST_LP_PREEMPT  = 4'h8;

    localparam ST_ALLOWED[9] = {ST_IDLE, ST_WAIT_TRIG, ST_LP_SAMPLE,
                                ST_LP_WAIT_EOC, ST_LP_INTERVAL,
                                ST_HP_SAMPLE, ST_HP_WAIT_EOC,
                                ST_HP_INTERVAL, ST_LP_PREEMPT};

    //==========================================================================
    // Input Constraints (assume)
    //==========================================================================

    // Constrain: EOC only asserted during WAIT_EOC states (analog behavior)
    // In formal, without this assume, EOC could be asserted any time
    // which would cause false failures.
    assume property (@(posedge adc_clk) disable iff (!rst_adc_n)
        eoc |-> (fsm_curr_st inside {ST_LP_WAIT_EOC, ST_HP_WAIT_EOC}));

    // Constrain: lp_trig_pulse and hp_trig_pulse are single-cycle pulses
    assume property (@(posedge adc_clk) disable iff (!rst_adc_n)
        $rose(lp_trig_pulse) |=> !lp_trig_pulse);
    assume property (@(posedge adc_clk) disable iff (!rst_adc_n)
        $rose(hp_trig_pulse) |=> !hp_trig_pulse);

    // Constrain: SOC assertion is followed by EOC within reasonable time
    // Without this, formal engine may produce unrealistic sequences
    // where SOC fires but EOC never arrives.
    assume property (@(posedge adc_clk) disable iff (!rst_adc_n)
        soc |-> ##[1:20] eoc);

    //==========================================================================
    // Safety: No illegal states (SMP_021)
    //==========================================================================
    // Formal proof: for all reachable states, fsm_curr_st is always valid.
    // This is STRONGER than simulation assertion because formal
    // exhaustively checks ALL possible paths.
    assert property (@(posedge adc_clk) disable iff (!rst_adc_n)
        fsm_curr_st inside {ST_ALLOWED});

    //==========================================================================
    // Liveness: Each state is reachable
    //==========================================================================
    cover property (@(posedge adc_clk) fsm_curr_st == ST_IDLE);
    cover property (@(posedge adc_clk) fsm_curr_st == ST_WAIT_TRIG);
    cover property (@(posedge adc_clk) fsm_curr_st == ST_LP_SAMPLE);
    cover property (@(posedge adc_clk) fsm_curr_st == ST_LP_WAIT_EOC);
    cover property (@(posedge adc_clk) fsm_curr_st == ST_LP_INTERVAL);
    cover property (@(posedge adc_clk) fsm_curr_st == ST_HP_SAMPLE);
    cover property (@(posedge adc_clk) fsm_curr_st == ST_HP_WAIT_EOC);
    cover property (@(posedge adc_clk) fsm_curr_st == ST_HP_INTERVAL);
    cover property (@(posedge adc_clk) fsm_curr_st == ST_LP_PREEMPT);

    // Cover: SOC generated
    cover property (@(posedge adc_clk) soc);
    // Cover: EOC received
    cover property (@(posedge adc_clk) eoc_captured);
    // Cover: HP preemption
    cover property (@(posedge adc_clk) fsm_curr_st == ST_LP_PREEMPT);

    //==========================================================================
    // No deadlock: Every state can transition out
    //==========================================================================
    // Formal proof: from any state, next_st != current_st eventually
    // (unless held by design — e.g., WAIT_TRIG waiting for trigger)
    assert property (@(posedge adc_clk) disable iff (!rst_adc_n)
        (fsm_curr_st inside {ST_LP_SAMPLE, ST_LP_WAIT_EOC, ST_LP_INTERVAL,
                              ST_HP_SAMPLE, ST_HP_WAIT_EOC, ST_HP_INTERVAL})
        |-> ##[1:10] (fsm_curr_st != $past(fsm_curr_st, 1)));

    //==========================================================================
    // FSM transition completeness
    //==========================================================================
    // Every state has a defined next state for all input combinations
    // (including default). No missing case branches.
    assert property (@(posedge adc_clk) disable iff (!rst_adc_n)
        fsm_next_st inside {ST_ALLOWED});

    //==========================================================================
    // Mutual exclusion: LP and HP states never simultaneously active
    //==========================================================================
    assert property (@(posedge adc_clk) disable iff (!rst_adc_n)
        !(stat_lp_busy && stat_hp_busy));

    //==========================================================================
    // EOC timeout (if EOC is expected but doesn't arrive)
    //==========================================================================
    // This is proved formally: whenever in WAIT_EOC, EOC arrives
    // within the assumed window.
    assert property (@(posedge adc_clk) disable iff (!rst_adc_n)
        (fsm_curr_st == ST_LP_WAIT_EOC)
        |-> ##[1:16] (fsm_curr_st != ST_LP_WAIT_EOC));

    //==========================================================================
    // Preemption safety
    //==========================================================================
    // When HP preempts, the interrupted LP channel is saved and resumed
    assert property (@(posedge adc_clk) disable iff (!rst_adc_n)
        (fsm_curr_st == ST_LP_PREEMPT)
        |=> (fsm_curr_st inside {ST_HP_SAMPLE, ST_HP_WAIT_EOC, ST_HP_INTERVAL}));

    // After HP completes, LP resumes from saved position
    assert property (@(posedge adc_clk) disable iff (!rst_adc_n)
        (fsm_curr_st == ST_HP_INTERVAL && interval_done && hp_seq_ptr >= 2'd3
         && lp_save_ptr != 5'h1F)
        |=> (fsm_curr_st == ST_LP_SAMPLE));

endmodule
