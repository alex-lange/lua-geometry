--[[
Port of the Poisson Disc Sampling algorithm by Martin Roberts:
"An improvement to Bridson's Algorithm for Poisson Disc sampling"
https://observablehq.com/@techsparx/an-improvement-on-bridsons-algorithm-for-poisson-disc-samp/2

The above implementation is a fork of Mike Bostock's implementation of Bridson's Algorithm:
https://observablehq.com/@mbostock/poisson-disc-distribution

A brief history of these functions is given at:
https://observablehq.com/@fil/poisson-distribution-generators
]]
local List = require((...):gsub("poisson%-disc%-sampler", "list"))
local Class = require((...):gsub("poisson%-disc%-sampler", "class"))

local PoissonDiscSampler = Class {}

function PoissonDiscSampler:init(width, height, radius)
  self.width = width
  self.height = height
  self.radius = radius

  self.k = 4 -- maximum number of samples before rejection
  self.epsilon = 0.0000001

  self.radius2 = radius * radius
  self.cellSize = radius * math.sqrt(1 / 2)

  self.gridWidth = math.ceil(width / self.cellSize)
  self.gridHeight = math.ceil(height / self.cellSize)

  -- initialize the grid to the max size we expect
  self.grid = {}
  for i = 1, self.gridWidth * self.gridHeight do
    self.grid[i] = false
  end

  -- The queue is the list of points already part of the sample that are potential parents for new points
  self.queue = List()
end

function PoissonDiscSampler:far(x, y)
  local i = math.floor(x / self.cellSize + 1)
  local j = math.floor(y / self.cellSize + 1)

  -- get neighboring cells
  local iLowerBound = math.max(i - 2, 1)
  local jLowerBound = math.max(j - 2, 1)
  local iUpperBound = math.min(i + 3, self.gridWidth + 1)
  local jUpperBound = math.min(j + 3, self.gridHeight + 1)

  for jj = jLowerBound, jUpperBound - 1 do
    local shift = jj * self.gridWidth
    for ii = iLowerBound, iUpperBound - 1 do
      local s = self.grid[shift + ii + 1]
      if s then
        local dx = s.x - x
        local dy = s.y - y
        if dx * dx + dy * dy < self.radius2 then
          return false
        end
      end
    end
  end
  return true
end

function PoissonDiscSampler:addToSample(x, y)
  local i = math.floor(x / self.cellSize + 1)
  local j = math.floor(y / self.cellSize + 1)
  local index = self.gridWidth * j + i + 1
  local s = {x = x, y = y}
  self.grid[index] = s
  self.queue:push_tail(s)
  return s
end

function PoissonDiscSampler:generate()
  if self.queue:len() == 0 then
    coroutine.yield({add = self:addToSample(self.width / 2, self.height / 2)})
  end

  while self.queue:len() > 0 do
    -- Pick a random element from the queue as the parent
    local i = math.random(1, self.queue:len())
    local parent = self.queue[i]
    local seed = math.random()

    -- try to find a new candidate between radius and 2 * radius from the parent
    local found = false
    for j = 0, self.k - 1 do
      local a = 2 * math.pi * (seed + j / self.k)
      local r = self.radius + self.epsilon
      local x = parent.x + r * math.cos(a)
      local y = parent.y + r * math.sin(a)

      if 0 <= x and x < self.width and 0 <= y and y < self.height and self:far(x, y) then
        found = true
        coroutine.yield({add = self:addToSample(x, y), parent = parent})
        break
      end
    end

    if not found then
      -- Remove the element from the queue by replacing it with the last element
      local r = self.queue:pop_tail()
      if i < self.queue:len() + 1 then
          self.queue:set(i, r)
      end
      coroutine.yield({remove = parent})
    end
  end

  self.done = true
  return true
end

return PoissonDiscSampler
