--[[
Lua port of the "incredibly fast and robust" Javascript Delaunator library, for Delaunay triangulation of 2D points

https://github.com/mapbox/delaunator/blob/71ea2625b22b264288abb285826f7a4dfb5e18ae/index.js

I kept the indexing zero-based, as in the original library, to avoid confusion with Lua's one-based indexing during the porting.

The default getX and getY functions assume that the points passed in is a one-based table of tables, where each table has an x and y field.
If you want to use a different format, the points tabe should include a getX and getY function that returns the x and y values of the point at the given 0-based index.
]]

--[[
Original license at the time of porting (2024-07-06):

ISC License

Copyright (c) 2021, Mapbox

Permission to use, copy, modify, and/or distribute this software for any purpose
with or without fee is hereby granted, provided that the above copyright notice
and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS
OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF
THIS SOFTWARE.
]]

local Class = require((...):gsub("delaunator", "class"))
local orient2d = require((...):gsub("delaunator", "orient2d"))
local List = require((...):gsub("delaunator", "list"))

local Delaunator = Class{}
local helpers = {}

local EPSILON = 2 ^ (-52)

function Delaunator.from(points)
  local n = #points
  local coords = {}

  if points.getX and points.getY then
    for i = 1, n do
      coords[i * 2 - 1] = points:getX(i)
      coords[i * 2] = points:getY(i)
    end
  else
    for i = 1, n do
      coords[i * 2 - 1] = points[i].x
      coords[i * 2] = points[i].y
    end
  end

  for i = 0, n - 1 do
    coords[i * 2] = points[i + 1].x
    coords[i * 2 + 1] = points[i + 1].y
  end

  return Delaunator(coords)
end

function Delaunator:init(coords)
  self.coords = coords
  local n = math.floor(#coords / 2)
  local maxTriangles = math.max(2 * n - 5, 0)

  -- tables that will store the triangulation graph
  self._triangles = {}
  for i = 0, maxTriangles * 3 - 1 do
    self._triangles[i] = 0
  end
  self._halfEdges = {}
  for i = 0, maxTriangles * 3 - 1 do
    self._halfEdges[i] = 0
  end

  -- temporary arrays for tracking the edges of the advancing convex hull
  self.hullPrev = {}
  self.hullNext = {}
  self.hullTri = {}
  self.hashSize = math.ceil(math.sqrt(n))
  self.hullHash = {}

  -- temporary arrays for sorting points
  self._ids = {}
  self._dists = {}

  for i = 0, n - 1 do
    self.hullPrev[i] = 0
    self.hullNext[i] = 0
    self.hullTri[i] = 0
    self._ids[i] = 0
    self._dists[i] = 0
  end

  for i = 0, self.hashSize - 1 do
    self.hullHash[i] = 0
  end
end

function Delaunator:update()
  local coords = self.coords
  local n = math.floor(#coords / 2)

  local minX = math.huge
  local minY = math.huge
  local maxX = -1 * math.huge
  local maxY = -1 * math.huge

  for i = 0, n - 1 do
    local x = coords[i * 2]
    local y = coords[i * 2 + 1]
    if x < minX then minX = x end
    if y < minY then minY = y end
    if x > maxX then maxX = x end
    if y > maxY then maxY = y end
    self._ids[i] = i
  end

  local cx = (minX + maxX) / 2
  local cy = (minY + maxY) / 2

  local i0, i1, i2 = nil, nil, nil

  -- pick a seed point close to the center
  local minDist = math.huge
  for i = 0, n - 1 do
    local d = helpers:dist(cx, cy, coords[i * 2], coords[i * 2 + 1])
    if d < minDist then
      i0 = i
      minDist = d
    end
  end
  local i0x = coords[i0 * 2]
  local i0y = coords[i0 * 2 + 1]

  -- find the point closest to the seed
  minDist = math.huge
  for i = 0, n - 1 do
    if i ~= i0 then
      local d = helpers:dist(i0x, i0y, coords[i * 2], coords[i * 2 + 1])
      if d < minDist and d > 0 then
        i1 = i
        minDist = d
      end
    end
  end
  local i1x = coords[i1 * 2]
  local i1y = coords[i1 * 2 + 1]

  -- find the third point which forms the smallest circumcircle with the first two
  local minRadius = math.huge
  for i = 0, n - 1 do
    if i ~= i0 and i ~= i1 then
      local r = helpers:circumradius(i0x, i0y, i1x, i1y, coords[i * 2], coords[i * 2 + 1])
      if r < minRadius then
        i2 = i
        minRadius = r
      end
    end
  end
  local i2x = coords[i2 * 2]
  local i2y = coords[i2 * 2 + 1]

  if minRadius == math.huge then
    for i = 0, n - 1 do
      local dx = coords[i * 2] - coords[0]
      local dy = coords[i * 2 + 1] - coords[1]
      if dx ~= false then
        self._dists[i] = dx
      else
        self._dists[i] = dy
      end
    end

    helpers:quickSort(self._ids, self._dists, 0, n - 1)
    local hull = {}
    local j = 0
    local d0 = -1 * math.huge
    for i = 0, n - 1 do
      local id = self._ids[i]
      local d = self._dists[id]
      if d > d0 then
        d0 = d
        hull[j] = id
        j = j + 1
      end
    end
    self.hull = hull
    self.triangles = {}
    self.halfEdges = {}
    return
  end

  -- swap the order of the seed points for counter-clockwise orientation
  if orient2d(i0x, i0y, i1x, i1y, i2x, i2y) < 0 then
    local i = i1
    local x = i1x
    local y = i1y
    i1 = i2
    i1x = i2x
    i1y = i2y
    i2 = i
    i2x = x
    i2y = y
  end

  self._cx, self._cy = helpers:circumcenter(i0x, i0y, i1x, i1y, i2x, i2y)
  for i = 0, n - 1 do
    self._dists[i] = helpers:dist(coords[i * 2], coords[i * 2 + 1], self._cx, self._cy)
  end

  -- sort the points by distance from the seed triangle circumcenter
  helpers:quickSort(self._ids, self._dists, 0, n - 1)

  -- set up the seed triangle as the starting hull
  if i0 == nil or i1 == nil or i2 == nil then
    error("i0, i1, i2 is nil")
  end
  self.hullStart = i0
  local hullSize = 3

  self.hullNext[i0] = i1
  self.hullPrev[i2] = i1

  self.hullNext[i1] = i2
  self.hullPrev[i0] = i2

  self.hullNext[i2] = i0
  self.hullPrev[i1] = i0

  self.hullTri[i0] = 0
  self.hullTri[i1] = 1
  self.hullTri[i2] = 2

  for i = 0, self.hashSize - 1 do
    self.hullHash[i] = -1
  end
  self.hullHash[self:hashKey(i0x, i0y)] = i0
  self.hullHash[self:hashKey(i1x, i1y)] = i1
  self.hullHash[self:hashKey(i2x, i2y)] = i2

  self.trianglesLen = 0
  self:addTriangle(i0, i1, i2, -1, -1, -1)

  local xp = nil
  local yp = nil
  for k = 0, #self._ids - 1 do
    local i = self._ids[k]
    local x = coords[i * 2]
    local y = coords[i * 2 + 1]

    -- skip near-duplicate points
    if k > 0 and xp ~= nil and yp ~= nil and math.abs(x - xp) <= EPSILON and math.abs(y - yp) <= EPSILON then
      goto continue1
    end
    xp = x
    yp = y

    -- skip seed triangle points
    if i == i0 or i == i1 or i == i2 then
      goto continue1
    end

    -- find a visible edge on the convex hull using edge hash
    local start = 0
    local key = self:hashKey(x, y)
    for j = 0, self.hashSize - 1 do
      start = self.hullHash[(key + j) % self.hashSize]
      if start ~= -1 and start ~= self.hullNext[start] then
        break
      end
    end
    start = self.hullPrev[start]

    local e = start
    local q = self.hullNext[e]
    while orient2d(x, y, coords[e * 2], coords[e * 2 + 1], coords[q * 2], coords[q * 2 + 1]) >= 0 do
      e = q
      if e == start then
        e = -1
        break
      end
      q = self.hullNext[e]
    end
    if e == -1 then -- likely a near-duplicate point; skip it
      goto continue1
    end

    -- add the first triangle from the point
    local t = self:addTriangle(e, i, self.hullNext[e], -1, -1, self.hullTri[e])

    -- recursively flip triangles from the point until they satisfy the Delaunay condition
    self.hullTri[i] = self:legalize(t + 2)
    self.hullTri[e] = t -- keep track of boundary triangles on the hull
    hullSize = hullSize + 1

    -- walk forward through the hull, adding more triangles and flipping recursively
    local next = self.hullNext[e]
    q = self.hullNext[next]
    while orient2d(x, y, coords[next * 2], coords[next * 2 + 1], coords[q * 2], coords[q * 2 + 1]) < 0 do
      t = self:addTriangle(next, i, q, self.hullTri[i], -1, self.hullTri[next])
      self.hullTri[i] = self:legalize(t + 2)
      self.hullNext[next] = next -- mark as removed
      hullSize = hullSize - 1
      next = q
      q = self.hullNext[next]
    end

    -- walk backward from the other side, adding more triangles and flipping
    if e == start then
      q = self.hullPrev[e]
      while orient2d(x, y, coords[q * 2], coords[q * 2 + 1], coords[e * 2], coords[e * 2 + 1]) < 0 do
        t = self:addTriangle(q, i, e, -1, self.hullTri[e], self.hullTri[q])
        self:legalize(t + 2)
        self.hullTri[q] = t
        self.hullNext[e] = e -- mark as removed
        hullSize = hullSize - 1
        e = q
        q = self.hullPrev[e]
      end
    end

    -- update the hull indices
    self.hullStart = e
    self.hullPrev[i] = e

    self.hullNext[e] = i
    self.hullPrev[next] = i
    self.hullNext[i] = next

    -- save the two new edges in the hash table
    self.hullHash[self:hashKey(x, y)] = i
    self.hullHash[self:hashKey(coords[e * 2], coords[e * 2 + 1])] = e

    ::continue1::
  end

  self.hull = {}
  local e = self.hullStart
  for i = 0, hullSize - 1 do
    self.hull[i] = e
    e = self.hullNext[e]
  end

  -- trim typed triangle mesh arrays
  self.triangles = {}
  self.halfEdges = {}

  for i = 0, self.trianglesLen - 1 do
    self.triangles[i] = self._triangles[i]
    self.halfEdges[i] = self._halfEdges[i]
  end

  self.done = true
end

function Delaunator:hashKey(x, y)
  return math.floor(helpers:psudoAngle(x - self._cx, y - self._cy) * self.hashSize) % self.hashSize
end

function Delaunator:addTriangle(i0, i1, i2, a, b, c)
  local t = self.trianglesLen

  self._triangles[t] = i0
  self._triangles[t + 1] = i1
  self._triangles[t + 2] = i2

  self:link(t, a)
  self:link(t + 1, b)
  self:link(t + 2, c)

  self.trianglesLen = self.trianglesLen + 3

  coroutine.yield()

  return t
end

function Delaunator:link(a, b)
  self._halfEdges[a] = b
  if b ~= -1 then
    self._halfEdges[b] = a
  end
end

function Delaunator:legalize(a)
  local ar = 0
  local edgeStack = List()

  -- recursion eliminated with a fixed-size stack
  while true do
    local b = self._halfEdges[a]

    -- if the pair of triangles doesn't satisfy the Delaunay condition
    -- (p1 is inside the circumcircle of [p0, pl, pr]), flip them,
    -- then do the same check/flip recursively for the new pair of triangles
    --
    --           pl                    pl
    --          /||\                  /  \
    --       al/ || \bl            al/    \a
    --        /  ||  \              /      \
    --       /  a||b  \    flip    /___ar___\
    --     p0\   ||   /p1   =>   p0\---bl---/p1
    --        \  ||  /              \      /
    --       ar\ || /br             b\    /br
    --          \||/                  \  /
    --           pr                    pr
    local a0 = a - a % 3
    ar = a0 + (a + 2) % 3

    if b == -1 then
      if edgeStack:len() == 0 then
        break
      end
      a = edgeStack:pop_tail()

      goto continue2
    end

    local b0 = b - b % 3
    local al = a0 + (a + 1) % 3
    local bl = b0 + (b + 2) % 3

    local p0 = self._triangles[ar]
    local pr = self._triangles[a]
    local pl = self._triangles[al]
    local p1 = self._triangles[bl]

    local illegal = helpers:inCircle(
      self.coords[p0 * 2], self.coords[p0 * 2 + 1],
      self.coords[pr * 2], self.coords[pr * 2 + 1],
      self.coords[pl * 2], self.coords[pl * 2 + 1],
      self.coords[p1 * 2], self.coords[p1 * 2 + 1]
    )

    if illegal then
      self._triangles[a] = p1
      self._triangles[b] = p0
      local hbl = self._halfEdges[bl]

      -- edge swapped on the other side of the hull (rare)
      if hbl == -1 then
        local e = self.hullStart
        repeat
          if self.hullTri[e] == bl then
            self.hullTri[e] = a
            break
          end
          e = self.hullNext[e]
        until e == self.hullStart
      end

      self:link(a, hbl)
      self:link(b, self._halfEdges[ar])
      self:link(ar, bl)

      local br = b0 + (b + 1) % 3

      edgeStack:push_tail(br)
      coroutine.yield()
    else
      if edgeStack:len() == 0 then
        break
      end
      a = edgeStack:pop_tail()
    end
    ::continue2::
  end

  return ar
end

function Delaunator:edgeIndicesOfTriangle(t)
  return 3 * t, 3 * t + 1, 3 * t + 2
end

function Delaunator:triangleIndexOfEdge(e)
  return math.floor(e / 3)
end

function Delaunator:pointsOfTriangle(t)
  local i, j, k = self:edgeIndicesOfTriangle(t)
  return self.triangles[i], self.triangles[j], self.triangles[k]
end


--[[
HELPERS
]]

-- monotonically increases with real angle, but doesn't need expensive trigonometry
function helpers:psudoAngle(dx, dy)
  local p = dx / (math.abs(dx) + math.abs(dy))
  if dy > 0 then
    return (3 - p) / 4
  else
    return (1 + p) / 4
  end
end

function helpers:dist(x1, y1, x2, y2)
  local dx = x2 - x1
  local dy = y2 - y1
  return dx * dx + dy * dy
end

function helpers:inCircle(ax, ay, bx, by, cx, cy, px, py)
  local dx = ax - px
  local dy = ay - py
  local ex = bx - px
  local ey = by - py
  local fx = cx - px
  local fy = cy - py

  local ap = dx * dx + dy * dy
  local bp = ex * ex + ey * ey
  local cp = fx * fx + fy * fy

  return dx * (ey * cp - bp * fy) -
         dy * (ex * cp - bp * fx) +
         ap * (ex * fy - ey * fx) < 0
end

function helpers:circumradius(ax, ay, bx, by, cx, cy)
  local dx = bx - ax
  local dy = by - ay
  local ex = cx - ax
  local ey = cy - ay

  local bl = dx * dx + dy * dy
  local cl = ex * ex + ey * ey
  local d = 0.5 / (dx * ey - dy * ex)

  local x = (ey * bl - dy * cl) * d
  local y = (dx * cl - ex * bl) * d

  return x * x + y * y
end

function helpers:circumcenter(ax, ay, bx, by, cx, cy)
  local dx = bx - ax
  local dy = by - ay
  local ex = cx - ax
  local ey = cy - ay

  local bl = dx * dx + dy * dy
  local cl = ex * ex + ey * ey
  local d = 0.5 / (dx * ey - dy * ex)

  local x = ax + (ey * bl - dy * cl) * d
  local y = ay + (dx * cl - ex * bl) * d

  return x, y
end

function helpers:orientFast(ax, ay, bx, by, cx, cy)
  return (ay - cy) * (bx - cx) - (ax - cx) * (by - cy)
end

function helpers:quickSort(ids, dists, left, right)
  if (right - left <= 20) then
    for i = left + 1, right do
      local temp = ids[i]
      local tempDist = dists[temp]
      local j = i - 1
      while j >= left and dists[ids[j]] > tempDist do
        ids[j + 1] = ids[j]
        j = j - 1
      end
      ids[j + 1] = temp
    end
  else
    local median = math.floor((left + right) / 2)
    local i = left + 1
    local j = right
    helpers:swap(ids, median, i)
    if dists[ids[left]] > dists[ids[right]] then
      helpers:swap(ids, left, right)
    end
    if dists[ids[i]] > dists[ids[right]] then
      helpers:swap(ids, i, right)
    end
    if dists[ids[left]] > dists[ids[i]] then
      helpers:swap(ids, left, i)
    end

    local temp = ids[i]
    local tempDist = dists[temp]
    while true do
      repeat
        i = i + 1
      until dists[ids[i]] >= tempDist
      repeat
        j = j - 1
      until dists[ids[j]] <= tempDist
      if j < i then
        break
      end
      helpers:swap(ids, i, j)
    end
    ids[left + 1] = ids[j]
    ids[j] = temp

    if right - i + 1 >= j - left then
      helpers:quickSort(ids, dists, i, right)
      helpers:quickSort(ids, dists, left, j - 1)
    else
      helpers:quickSort(ids, dists, left, j - 1)
      helpers:quickSort(ids, dists, i, right)
    end
  end
end

function helpers:swap(arr, i, j)
  local temp = arr[i]
  arr[i] = arr[j]
  arr[j] = temp
end

return Delaunator
