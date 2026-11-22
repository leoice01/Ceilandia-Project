--!strict

-- PROVISÓRIO (P4)
local KillFeedConfig = {
	EndpointUrl = "https://killfeed-bot-production.up.railway.app/kills",
	FlushInterval = 2,
	BatchSize = 10,
	QueueCap = 200,
	BackoffBase = 2,
	BackoffMax = 60,
	CloseTimeout = 5,
	AttributionWindow = 1,
}

return KillFeedConfig