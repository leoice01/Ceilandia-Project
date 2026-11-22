--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local Payload = require(ServerScriptService.Server.KillFeed.Payload)
local Queue = require(ServerScriptService.Server.KillFeed.Queue)
local Zones = require(ServerScriptService.Server.KillFeed.Zones)

local function makeMockPlayer(userId: number, name: string, displayName: string, faction: string?)
	return {
		UserId = userId,
		Name = name,
		DisplayName = displayName,
		Team = nil,
		GetAttribute = function(_self: any, attr: string)
			if attr == "Faction" then
				return faction
			end
			return nil
		end,
	}
end

return function()
	describe("Payload", function()
		it("handles nil killer as Ambiente", function()
			local victim = makeMockPlayer(10, "vini", "Vini", "Bandido")
			local entry = Payload.build({
				victim = victim,
				killer = nil,
				cause = "environment",
				position = Vector3.new(10.4, 5.6, -3.2),
				time = 1700000000,
				jobId = "abcdef123456",
				placeId = 999,
			})

			expect(entry.killer).to.equal(nil)
			expect(entry.killerLabel).to.equal("Ambiente")
			expect(entry.victim.team).to.equal("Ladrão")
			expect(entry.zone).to.equal("Rua")
			expect(entry.jobId).to.equal("abcdef12")
			expect(entry.position.x).to.equal(10)
			expect(entry.position.y).to.equal(6)
		end)

		it("handles self-kill as Suicídio", function()
			local player = makeMockPlayer(20, "leo", "Leo", "Policia")
			local entry = Payload.build({
				victim = player,
				killer = player,
				weaponName = "Granada",
				cause = "combat",
				distance = 4.56,
				headshot = false,
				time = 1700000001,
				jobId = "",
				placeId = 1,
			})

			expect(entry.victim.team).to.equal("Polícia")
			expect(entry.killerLabel).to.equal("Suicídio")
			expect(entry.distance).to.equal(4.6)
			expect(entry.jobId).to.equal("studio")
		end)
	end)

	describe("Zones", function()
		it("returns Rua when no Zones folder exists", function()
			expect(Zones.findZone(Vector3.new(0, 0, 0), nil)).to.equal("Rua")
		end)
	end)

	describe("Queue", function()
		it("enforces cap by dropping oldest items and takes batches FIFO", function()
			local q = Queue.new(3, 2, 60) :: Queue.Queue<number>
			q:push(1)
			q:push(2)
			q:push(3)
			q:push(4)

			expect(q:size()).to.equal(3)
			local batch = q:take(2)
			expect(#batch).to.equal(2)
			expect(batch[1]).to.equal(2)
			expect(batch[2]).to.equal(3)
			expect(q:size()).to.equal(1)
		end)

		it("applies exponential backoff capped at max", function()
			local q = Queue.new(10, 2, 60) :: Queue.Queue<number>
			expect(q:recordFailure(100)).to.equal(2)
			expect(q:canSend(101)).to.equal(false)
			expect(q:canSend(102)).to.equal(true)
			expect(q:recordFailure(102)).to.equal(4)
			q:recordSuccess()
			expect(q:canSend(103)).to.equal(true)
		end)
	end)
end