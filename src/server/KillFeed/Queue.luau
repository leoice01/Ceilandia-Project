--!strict

export type Queue<T> = {
	push: (self: Queue<T>, item: T) -> (),
	pushFront: (self: Queue<T>, batch: { T }) -> (),
	take: (self: Queue<T>, count: number) -> { T },
	size: (self: Queue<T>) -> number,
	isEmpty: (self: Queue<T>) -> boolean,
	canSend: (self: Queue<T>, now: number) -> boolean,
	recordFailure: (self: Queue<T>, now: number) -> number,
	recordSuccess: (self: Queue<T>) -> (),
}

local QueueModule = {}

function QueueModule.new<T>(cap: number, backoffBase: number, backoffMax: number): Queue<T>
	local items: { T } = {}
	local consecutiveFailures = 0
	local nextRetryAt = 0

	local self = {} :: Queue<T>

	function self:push(item: T)
		if #items >= cap then
			table.remove(items, 1)
		end
		table.insert(items, item)
	end

	function self:pushFront(batch: { T })
		local n = #batch
		if n == 0 then
			return
		end
		-- Reconstrói mantendo a ordem original do lote na frente dos itens atuais
		local combined: { T } = table.create(n + #items)
		for i = 1, n do
			combined[i] = batch[i]
		end
		for i = 1, #items do
			combined[n + i] = items[i]
		end
		local overflow = #combined - cap
		if overflow > 0 then
			for i = 1, cap do
				combined[i] = combined[i + overflow]
			end
			for i = cap + 1, #combined do
				combined[i] = nil
			end
		end
		items = combined
	end

	function self:take(count: number): { T }
		local n = math.min(count, #items)
		local batch: { T } = table.create(n)
		for i = 1, n do
			batch[i] = items[i]
		end
		-- Remove do início mantendo a ordem FIFO
		if n > 0 then
			local remaining = #items - n
			for i = 1, remaining do
				items[i] = items[i + n]
			end
			for i = remaining + 1, #items do
				items[i] = nil
			end
		end
		return batch
	end

	function self:size(): number
		return #items
	end

	function self:isEmpty(): boolean
		return #items == 0
	end

	function self:canSend(now: number): boolean
		return now >= nextRetryAt
	end

	function self:recordFailure(now: number): number
		consecutiveFailures += 1
		local delay = math.min(backoffBase * (2 ^ (consecutiveFailures - 1)), backoffMax)
		nextRetryAt = now + delay
		return delay
	end

	function self:recordSuccess()
		consecutiveFailures = 0
		nextRetryAt = 0
	end

	return self
end

return QueueModule