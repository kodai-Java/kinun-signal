CREATE TABLE IF NOT EXISTS watchlists (
    ticker VARCHAR(16) PRIMARY KEY,
    company_name VARCHAR(255) NOT NULL,
    target_discount_rate DOUBLE PRECISION NOT NULL DEFAULT 20.0,
    last_earnings_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS theoretical_prices (
    id SERIAL PRIMARY KEY,
    ticker VARCHAR(16) NOT NULL REFERENCES watchlists(ticker) ON DELETE CASCADE,
    trigger_type VARCHAR(50) NOT NULL, -- 'INITIAL', 'EARNINGS_UPDATE', 'MANUAL'
    base_price DOUBLE PRECISION NOT NULL,
    bull_price DOUBLE PRECISION NOT NULL,
    bear_price DOUBLE PRECISION NOT NULL,
    net_cash DOUBLE PRECISION NOT NULL,
    free_cash_flow DOUBLE PRECISION NOT NULL,
    shares_outstanding DOUBLE PRECISION NOT NULL,
    wacc DOUBLE PRECISION NOT NULL,
    growth_rate_base DOUBLE PRECISION NOT NULL,
    growth_rate_bull DOUBLE PRECISION NOT NULL,
    growth_rate_bear DOUBLE PRECISION NOT NULL,
    terminal_growth_rate DOUBLE PRECISION NOT NULL,
    reasoning_ja TEXT NOT NULL,
    calculated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS daily_prices (
    id SERIAL PRIMARY KEY,
    ticker VARCHAR(16) NOT NULL REFERENCES watchlists(ticker) ON DELETE CASCADE,
    trade_date DATE NOT NULL,
    close_price DOUBLE PRECISION NOT NULL,
    divergence_rate DOUBLE PRECISION NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(ticker, trade_date)
);

CREATE TABLE IF NOT EXISTS alert_logs (
    id SERIAL PRIMARY KEY,
    ticker VARCHAR(16) NOT NULL,
    alert_type VARCHAR(50) NOT NULL, -- 'UNDERVALUED', 'EARNINGS', 'NEWS_SUMMARY', 'INITIAL_CALC'
    message TEXT NOT NULL,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
