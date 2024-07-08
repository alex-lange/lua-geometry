local epsilon = 1.1102230246251565e-16

local ccwerrboundA = (3 + 16 * epsilon) * epsilon
-- local ccwerrboundB = (2 + 12 * epsilon) * epsilon
-- local ccwerrboundC = (9 + 64 * epsilon) * epsilon * epsilon

local function orient2d(ax, ay, bx, by, cx, cy)
  local detleft = (ay - cy) * (bx - cx)
  local detright = (ax - cx) * (by - cy)
  local det = detleft - detright

  local detsum = math.abs(detleft + detright)

  if math.abs(det) >= ccwerrboundA * detsum then
    return det
  end

  error("orient2d-adapt not fully tested yet. Only use this function on non-degenerate triangles.")
end

return orient2d
