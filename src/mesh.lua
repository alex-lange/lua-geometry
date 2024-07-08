--[[
Wrapper around Delaunator's Delaunay triangulation and its dual Voronoi diagram.

This is based on Amit Patel's amazing writing on Delaunay triangles, Vornoi cells, and polygonal map generation, particularly:

"Delaunator Guide"
https://mapbox.github.io/delaunator/

"Data structure for triangle meshes"
https://www.redblobgames.com/x/1722-b-rep-triangle-meshes/

This code is mostly a Lua port of the JavaScript code from the above articles and their dual-mesh repository:
https://github.com/redblobgames/dual-mesh/blob/c26618aec07af7e14b2c8ebbb97cd137c3f06c18/index.js
]]

--[[
From the dual-mesh repository and source code:

From https://github.com/redblobgames/dual-mesh
Copyright 2017 Red Blob Games <redblobgames@gmail.com>
License: Apache v2.0 <http://www.apache.org/licenses/LICENSE-2.0.html>
]]

local Class = require((...):gsub("mesh", "class"))

local Mesh = Class {}

local function triangleFromSide(side)
  return math.floor(side / 3)
end

local function previousSide(side)
  if side % 3 == 0 then
    return side + 2
  else
    return side - 1
  end
end

local function nextSide(side)
  if side % 3 == 2 then
    return side - 2
  else
    return side + 1
  end
end

function Mesh:init(points, delaunator)
  self.cellVertices = {}
  -- shift points from index-1 to index-0
  for i = 1, #points do
    self.cellVertices[i - 1] = { x = points[i].x, y = points[i].y }
  end

  self._triangles = delaunator.triangles
  self._halfEdges = delaunator.halfEdges

  self.numSides = #self._triangles + 1 -- add 1 because Lua indexes by 1 not 0 so it doesn't got the 0 index as part of the length
  if self.numSides % 3 ~= 0 then
    error("Invalid number of sides is not divisble by 3: " .. self.numSides)
  end
  self.numCells = #self.cellVertices + 1
  self.numTriangles = self.numSides / 3

  self.triangleVertices = {}
  for i = 0, self.numTriangles - 1 do
    self.triangleVertices[i] = { x = 0 , y = 0 }
  end
  log.info("max i = " .. self.numTriangles - 1)
end

function Mesh:load()
  -- Construct an index for finding sides connected to a cell
  self.sideOfCell = {}
  for s = 0, self.numSides - 1 do
    local endpoint = self._triangles[nextSide(s)]
    if (self.sideOfCell[endpoint] == nil or self._halfEdges[s] == -1) then
      self.sideOfCell[endpoint] = s
    end
  end

  -- Construct triangle coordinates
  for s = 0, self.numSides - 1, 3 do
    local t = math.floor(s / 3)
    local a = self.cellVertices[self._triangles[s]]
    local b = self.cellVertices[self._triangles[s + 1]]
    local c = self.cellVertices[self._triangles[s + 2]]

    -- TODO: Check if ghost
    -- ghost triangle center is just outside the unpaired side
    -- solid triangle center is at the centroid
    self.triangleVertices[t].x = (a.x + b.x + c.x) / 3
    self.triangleVertices[t].y = (a.y + b.y + c.y) / 3
  end
end

function Mesh:cellPosition(cell)
  return self.cellVertices[cell]
end

function Mesh:trianglePosition(triangle)
  return self.triangleVertices[triangle]
end


-- A side is directed. If two triangles t0, t1 are adjacent, there will
-- be two sides representing the boundary, one for t0 and one for t1. These
-- can be accessed with triangleWithInnerSide and triangleWithOuterSide.
function Mesh:triangleWithInnerSide(s)
  return triangleFromSide(s)
end

function Mesh:triangleWithOuterSide(s)
  return triangleFromSide(self._halfEdges[s])
end

-- A side also represents the boundary between two cells. If two cells
-- r0, r1 are adjacent, there will be two sides representing the boundary,
-- cellWithBeginningSide and cellWithEndingSide.
function Mesh:cellWithBeginningSide(s)
  return self._triangles[s]
end

function Mesh:cellWithEndingSide(s)
  return self._triangles[nextSide(s)]
end


function Mesh:nextSide(s)
  return nextSide(s)
end

function Mesh:previousSide(s)
  return previousSide(s)
end

-- A side from p-->q will have a pair q-->p, at index
-- s_opposite_s. It will be -1 if the side doesn't have a pair.
-- Use addGhostStructure() to add ghost pairs to all sides.

function Mesh:oppositeSide(s)
  return self._halfEdges[s]
end

function Mesh:sidesAroundTriangle(t)
  return { t * 3, t * 3 + 1, t * 3 + 2 }
end

function Mesh:cellsAroundTriangle(t)
  local a, b, c = self:sidesAroundTriangle(t)
  return { self._triangles[a], self._triangles[b], self._triangles[c] }
end

function Mesh:trianglesAroundTriangle(t)
  local a, b, c = self:sidesAroundTriangle(t)
  return { self:triangleWithOuterSide(a), self:triangleWithOuterSide(b), self:triangleWithOuterSide(c) }
end

function Mesh:sidesAroundCell(r)
  local s = self.sideOfCell[r]
  local incoming = s
  local sides = {}

  if s == nil then
    return sides
  end

  while true do
    table.insert(sides, self:oppositeSide(incoming))
    local outgoing = self:nextSide(incoming)
    incoming = self:oppositeSide(outgoing)
    if incoming == -1 or incoming == s or incoming == nil then
      break
    end
  end
  return sides
end

function Mesh:sidePositionsAroundCell(c)
  local sides = self:sidesAroundCell(c)
  local positions = {}
  for _, s in ipairs(sides) do
    local t = triangleFromSide(s)
    table.insert(positions, self:trianglePosition(t))
  end
  return positions
end

function Mesh:cellsAroundCell(r)
  local s = self.sideOfCell[r]
  local incoming = s
  local cells = {}
  while true do
    table.insert(cells, self:cellWithBeginningSide(incoming))
    local outgoing = self:nextSide(incoming)
    incoming = self:oppositeSide(outgoing)
    if incoming == -1 or incoming == s then
      break
    end
  end
end

function Mesh:trianglesAroundCell(r)
  local s = self.sideOfCell[r]
  local incoming = s
  local triangles = {}
  while true do
    table.insert(triangles, self:triangleFromSide(incoming))
    local outgoing = self:nextSide(incoming)
    incoming = self:oppositeSide(outgoing)
    if incoming == -1 or incoming == s then
      break
    end
  end
  return triangles
end

function Mesh:forEachCellEdge(callback)
  for e = 0, self.numSides - 1 do
    if (e < self._halfEdges[e]) then
      local p1 = self:trianglePosition(self:triangleWithInnerSide(e))
      local p2 = self:trianglePosition(self:triangleWithOuterSide(e))
      callback(p1, p2)
    end
  end
end

return Mesh
