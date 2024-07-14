--[[
Wrapper around Delaunator's Delaunay triangulation and its dual Voronoi diagram.

This is based on Amit Patel's amazing writing on Delaunay triangles, Vornoi cells, and polygonal
map generation, particularly:

"Delaunator Guide"
https://mapbox.github.io/delaunator/

"Data structure for triangle meshes"
https://www.redblobgames.com/x/1722-b-rep-triangle-meshes/

Their dual-mesh repository which implements the above ideas:
https://github.com/redblobgames/dual-mesh/blob/c26618aec07af7e14b2c8ebbb97cd137c3f06c18/index.js

Licence from https://github.com/redblobgames/dual-mesh
Copyright 2017 Red Blob Games <redblobgames@gmail.com>
License: Apache v2.0 <http://www.apache.org/licenses/LICENSE-2.0.html>
]]

--[[
This is the summary of my understanding of the above resources:

This Mesh class represents a Delaunay triangulation and its dual Voronoi diagram with minimal
amount of data. The data we need to store is:
  - the voronoi cells (c)
  - the delaunay triangles (t)
  - the "edges" (e), each representing both an edge of a triangle and an edge of a cell.

Each element has an id:
  - 0 <= c < numCells
  - 0 <= t < numTriangles
  - 0 <= e < numEdges

We can represent both types of edges with the same table because each triangle edge
intersects with exactly one cell edge:

Delaunay Triangulation:          Voronoi Cell:
     .         .                  .         .
    / \       / \                / \  /O\  / \
   /   \     /   \              /   \/   \/   \
  /     \   /     \            /   O/\   /\O   \
 /_______\ /_______\          /____|__\ /__|____\
 \       / \       /          \    |  / \  |    /
  \     /   \     /            \   O\/   \/O   /
   \   /     \   /              \   /\   /\   /
    \ /       \ /                \ /  \O/  \ /
     .         .                  .         .

Each Cell contains exactly one Triangle point (i.e. one seed point of the triangluation), and each
Triangle contains exactly one Cell point (defined as the center/centroid of the Triangle). We store
these points in the _cellPositions and _trianglePositions tables, respectively.

Delaunator stores each edge as two half-edges. This is so that each triangle has a unique half-edge,
(and results in the number of edges being the same as the number of cells and the number of triangles!).
The neighboring triangle has the opposite half-edge.
  - delaunator.triangles[e] contains the index of a point where the half-edge of a triangle starts,
    and therefore this point is also the position of a cell that intersects with this triangle.
  - the half-edges of a triangle are indexed consecutively, so the three points of a triangle are:
      delaunator.triangles[e], delaunator.triangles[e + 1], delaunator.triangles[e + 2]
  - for half-edge e, the triangleOfEdge(e) connects two seed points (/ cell positions), delaunay.triangles[e] and delaunay.triangles[nextHalfedge(e)]

  - delaunator.halfEdges[e] contains the index of the opposite half-edge of the neighboring triangle
  - the cell'a half-edge connects two cell points, which are the centers of triangleOfEdge(e) and triangleOfEdge(delaunay.halfedges[e])
]]

local Class = require((...):gsub("mesh", "class"))

local Mesh = Class {}

local function triangleOfEdge(side)
  return math.floor(side / 3)
end

function Mesh:init(points, delaunator)
  self._cellPositions = {}
  -- shift points from index-1 to index-0
  for i = 1, #points do
    self._cellPositions[i - 1] = { x = points[i].x, y = points[i].y }
  end

  self._triangles = delaunator.triangles
  self._halfEdges = delaunator.halfEdges

  self.numEdges = #self._triangles + 1 -- add 1 because Lua indexes by 1 not 0 so it doesn't got the 0 index as part of the length
  if self.numEdges % 3 ~= 0 then
    error("Invalid number of sides is not divisble by 3: " .. self.numEdges)
  end
  self.numCells = #self._cellPositions + 1
  self.numTriangles = self.numEdges / 3

  self._trianglePositions = {}
  for i = 0, self.numTriangles - 1 do
    self._trianglePositions[i] = { x = 0 , y = 0 }
  end
  log.info("max i = " .. self.numTriangles - 1)
end

function Mesh:load()
  -- Construct an index for finding sides connected to a cell
  self.sideOfCell = {}
  for c = 0, self.numEdges - 1 do
    local endpoint = self._triangles[self:nextHalfEdge(c)]
    if (self.sideOfCell[endpoint] == nil or self._halfEdges[c] == -1) then
      self.sideOfCell[endpoint] = c
    end
  end

  -- Construct triangle coordinates
  for s = 0, self.numEdges - 1, 3 do
    local t = math.floor(s / 3)
    local a = self._cellPositions[self._triangles[s]]
    local b = self._cellPositions[self._triangles[s + 1]]
    local c = self._cellPositions[self._triangles[s + 2]]

    -- TODO: Check if ghost
    -- ghost triangle center is just outside the unpaired side
    -- solid triangle center is at the centroid
    self._trianglePositions[t].x = (a.x + b.x + c.x) / 3
    self._trianglePositions[t].y = (a.y + b.y + c.y) / 3
  end
end

function Mesh:cellPosition(cell)
  return self._cellPositions[cell]
end

function Mesh:trianglePosition(triangle)
  return self._trianglePositions[triangle]
end

-- Given a side of a triangle, return the next side of that same triangle.
-- (0 -> 1, 1 -> 2, 2 -> 0)
function Mesh:nextHalfEdge(edge)
  if edge % 3 == 2 then
    return edge - 2
  else
    return edge + 1
  end
end

-- Given a side of a triangle, return the previous side of that same triangle.
-- (0 -> 2, 2 -> 1, 1 -> 0)
function Mesh:previousHalfEdge(edge)
  if edge % 3 == 0 then
    return edge + 2
  else
    return edge - 1
  end
end

-- A side is directed. If two triangles t0, t1 are adjacent, there will
-- be two sides representing the boundary, one for t0 and one for t1. These
-- can be accessed with triangleWithInnerSide and triangleWithOuterSide.
function Mesh:triangleWithInnerSide(s)
  return triangleOfEdge(s)
end

function Mesh:triangleWithOuterSide(s)
  return triangleOfEdge(self._halfEdges[s])
end

-- A side also represents the boundary between two cells. If two cells
-- are adjacent, there will be two sides representing the boundary,
-- cellWithInnerSide and cellWithOuterSide.
function Mesh:cellWithInnerSide(s)
  return self._triangles[s]
end

function Mesh:cellWithOuterSide(s)
  -- return self._triangles[self._halfEdges[s]] -- pretty sure this works but nextHalfEdge is fine too
  return self._triangles[self:nextHalfEdge(s)]
end

-- A side from p-->q will have a pair q-->p, at index
-- oppositeSide(side). It will be -1 if the side doesn't have a pair.
-- Use addGhostStructure() to add ghost pairs to all sides.
function Mesh:oppositeSide(s)
  return self._halfEdges[s]
end

function Mesh:edgesOfTriangle(t)
  return t * 3, t * 3 + 1, t * 3 + 2
end

function Mesh:cellsAroundTriangle(t)
  local a, b, c = self:edgesOfTriangle(t)
  return { self._triangles[a], self._triangles[b], self._triangles[c] }
end

function Mesh:trianglesAroundTriangle(t)
  local a, b, c = self:edgesOfTriangle(t)
  return { self:triangleWithOuterSide(a), self:triangleWithOuterSide(b), self:triangleWithOuterSide(c) }
end

--[[
     /| |\       a = incoming
    / | | \      b = nextHalfEdge(a) = outgoing
   /  ^ |  ^     c = oppositeSide(b) = incoming
  /   b c   \    d = nextHalfEdge(c) = outgoing
 V    | V    \   ...
/_a_>_| |_d_>_\
]]
function Mesh:sidesAroundCell(r)
  local s = self.sideOfCell[r]
  local incoming = s
  local sides = {}

  if s == nil then
    return sides
  end

  while true do
    table.insert(sides, self:oppositeSide(incoming))
    local outgoing = self:nextHalfEdge(incoming)
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
    local t = self:triangleWithInnerSide(s)
    table.insert(positions, self:trianglePosition(t))
  end
  return positions
end

function Mesh:cellsAroundCell(r)
  local s = self.sideOfCell[r]
  local incoming = s
  local cells = {}
  while true do
    table.insert(cells, self:cellWithInnerSide(incoming))
    local outgoing = self:nextHalfEdge(incoming)
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
    table.insert(triangles, self:triangleWithInnerSide(incoming))
    local outgoing = self:nextHalfEdge(incoming)
    incoming = self:oppositeSide(outgoing)
    if incoming == -1 or incoming == s then
      break
    end
  end
  return triangles
end

function Mesh:pointsOfCellSide(e)
  local p1 = self:trianglePosition(self:triangleWithInnerSide(e))
  local p2 = self:trianglePosition(self:triangleWithOuterSide(e))
  return p1, p2
end

function Mesh:forEachCellEdge(callback)
  for e = 0, self.numEdges - 1 do
    if (e < self._halfEdges[e]) then
      local p1, p2 = self:pointsOfCellSide(e)
      callback(p1, p2)
    end
  end
end

function Mesh:forEachTriangleEdge(callback)
  for e = 0, self.numEdges - 1 do
    if (e < self._halfEdges[e]) then
      local p1 = self:cellPosition(self._triangles[e])
      local p2 = self:cellPosition(self._triangles[self:nextHalfEdge(e)])
      if p1 and p2 then
        callback(p1, p2)
      end
    end
  end
end

-- function Mesh:forEachTriangle(callback)
--   for t = 0, self.numSides / 3 - 1 do
--     local i, j, k = self:sidesAroundTriangle(t)
--     local a = self:cellPosition(i)
--     local b = self:cellPosition(j)
--     local c = self:cellPosition(k)
--     if a and b and c then
--       callback(a, b, c)
--     end
--   end
-- end

return Mesh
