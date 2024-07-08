--[[
Slightly modified version of the table_list.lua from TheAlgorithms/Lua repository

https://github.com/TheAlgorithms/Lua/blob/d594ea37578f32965a07967d6e44ef1f8c108108/src/data_structures/table_list.lua
]]

--[[
Original Repository License:
MIT License

Copyright (c) 2023 Lars Müller and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

-- Table based list, can handle up to 2^52 elements
-- See https://www.lua.org/pil/11.4.html

local Class = require((...):gsub("table_list", "class"))

local List = Class {}

function List:init()
	self._head_index = 0 -- zero-based head index simplifies one-based list indices
	self._length = #self
	return self
end

function List:len()
	-- list length
	return self._length
end

function List:in_bounds(index)
	-- boolean whether the index is in list bounds
	return index >= 1 and index <= self:len()
end

function List:get(
	index -- index from 1 (head) to length (tail)
)
	assert(self:in_bounds(index))
	return self[self._head_index + index]
end

function List:set(
	-- index from 1 (head) to length (tail)
	index,
	-- value to set
	value
)
	assert(self:in_bounds(index) and value ~= nil)
	self[self._head_index + index] = value
end

function List:ipairs()
	local index = 0
	-- iterator -> index, value
	return function()
		index = index + 1
		if index > self._length then
			return
		end
		return index, self[self._head_index + index]
	end
end

function List:rpairs()
	local index = self._length + 1
	-- reverse iterator (starting at tail) -> index, value
	return function()
		index = index - 1
		if index < 1 then
			return
		end
		return index, self[self._head_index + index]
	end
end

function List:push_tail(value)
	assert(value ~= nil)
	self._length = self._length + 1
	self[self._head_index + self._length] = value
end

function List:get_tail()
	return self[self._head_index + self._length]
end

function List:pop_tail()
	if self._length == 0 then
		return
	end
	local value = self:get_tail()
	self[self._head_index + self._length] = nil
	self._length = self._length - 1
	return value
end

function List:push_head(value)
	self[self._head_index] = value
	self._head_index = self._head_index - 1
	self._length = self._length + 1
end

function List:get_head()
	return self[self._head_index + 1]
end

function List:pop_head()
	if self._length == 0 then
		return
	end
	local value = self:get_head()
	self._head_index = self._head_index + 1
	self._length = self._length - 1
	self[self._head_index] = nil
	return value
end

return List
