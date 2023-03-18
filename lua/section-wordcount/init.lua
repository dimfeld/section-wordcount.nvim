local api = vim.api
local ns_id
local highlight

local M = {}

local function line_wordcount(line)
  -- Replace each word with empty string and it returns the number of words replaced.
  _, n = line:gsub("%w+", "")
  return n
end

local buffer_data = {}

local function find_region_at_line(data, line_num)
  for i, region in ipairs(data.regions)  do
    if region.line_num == line_num then
      return i, region
    end
  end

  return nil, nil
end

local function find_insert_position(data, line_num)
  for i, region in ipairs(data.regions) do
    if region.line_num > line_num then
      return i
    end
  end
  return #data.regions + 1
end

local function add_region(data, line_num, header_level)
  local region = {
    line_num = line_num,
    level = #header_level,
    wordcount = nil,
    virt_text = ""
  }

  local pos = find_insert_position(data, line_num)
  data.regions_by_line[line_num] = region
  table.insert(data.regions, pos, region)
  return region
end

local function delete_region(data, line_num)
  local region = data.regions_by_line[line_num]
  if region then
    data.regions_by_line[line_num] = nil
    local i, _ = find_region_at_line(data, line_num)
    table.remove(data.regions, i)
  end
end

local function set_marker(data, line, text)
end

local function update_wordcounts(data, start_line, end_line)
  -- Figure out which range of markers we potentially need to update.
  -- This will be the closest level 1 heading before start_line, up through the last
  -- heading of any level before end_line.
  local start_index = 1
  for i, region in ipairs(data.regions) do
    if region.line_num >= start_line then
      break
    end

    if region.level == 1 then
      start_index = i
    end
  end

  local end_index = start_index
  while end_index <= #data.regions do
    local region_line = data.regions[end_index].line_num
    -- vim.pretty_print({
    --   end_index=end_index,
    --   region_line=region_line,
    --   end_line=end_line
    -- })
    if region_line > end_line then
      break
    end
    end_index = end_index + 1
  end

  end_index = end_index - 1

  -- Update the markers for the regions in the range
  -- A dynamic programming approach could help here. For now we don't do that.
  for i = start_index, end_index do
    local region = data.regions[i]
    local region_line = region.line_num
    local wordcount = 0

    -- Find the next region with level <= this region's level.
    local end_count_region
    for j = i + 1, #data.regions do
      local next_region = data.regions[j]
      if next_region.level <= region.level then
        end_count_region = next_region
        break
      end
    end

    local count_end_line = end_count_region and (end_count_region.line_num - 1) or table.maxn(data.line_counts)

    for j = region_line + 1, count_end_line do
      local line_count = data.line_counts[j]
      if line_count then
        wordcount = wordcount + line_count
      end
    end

    local needs_redraw = false
    if wordcount ~= region.wordcount then
      region.wordcount = wordcount
      region.virt_text = string.format("%d Words", wordcount)
      -- vim.pretty_print('update', region)
    end
  end

end

-- Keep of list of regions
-- Each region has:
-- The extmark ID for the region
-- The header level
-- The list of lines along with counts.
-- A cached value for the previous word count sum for this region
--
-- When counting the words for a header, we start with the current entry and go down, summing all the counts, until we see a header with the
-- same or higher level. The resulting value becomes the count for this region.

M.wordcounter = function(options)
  options = options or {}
  local header_char = options.header_char or "#"
  local header_re = "^" .. header_char .. "+"

  local bufnr = api.nvim_get_current_buf()

  local data = {
    bufnr = bufnr,
    regions = {},
    regions_by_line = {},
    line_counts = {},
    line_markers = {},
  }

  buffer_data[bufnr] = data

  local function handle_change(first_line, last_line, new_last_line)
    -- Convert to 1-based indexing for Lua. We use this more often, and so just convert back to VIM zero-based indexing
    -- when calling the API.
    first_line = first_line + 1
    last_line = last_line + 1
    new_last_line = new_last_line + 1

    local line_diff = new_last_line - last_line
    if line_diff > 0 then
      -- Inserted lines
      -- print(string.format("Inserted %d lines at %d", line_diff, last_line))
      for i = 1, line_diff do
        table.insert(data.line_counts, last_line, nil)
      end
    elseif line_diff < 0 then
      -- Deleted lines
      -- print(string.format("Removed %d lines at %d", -line_diff, last_line))
      for i = 1, -line_diff do
        table.remove(data.line_counts, last_line)
      end
    end

    -- Update all regions past the end of the updated area.
    if line_diff ~= 0 then

      for _, region in ipairs(data.regions) do
        if region.line_num >= last_line then
          -- vim.pretty_print('move region', region, line_diff)

          if data.regions_by_line[region.line_num] == region then
            -- Need to check in case an earlier iteration of this loop changed the value for this line.
            data.regions_by_line[region.line_num] = nil
          end

          region.line_num = region.line_num + line_diff

          data.regions_by_line[region.line_num] = region
        end
      end
    end

    last_line = math.max(last_line, new_last_line)

    -- Expand the range to cover the lines just before and after the changed lines. This helps
    -- with cases where the marker gets moved onto the wrong line.
    local buffer_line_count = api.nvim_buf_line_count(0) + 1

    -- Recalculate line counts for the changed lines
    local lines = api.nvim_buf_get_lines(0, first_line - 1, last_line - 1, false)
    --vim.pretty_print({first_line, last_line, new_last_line, lines, marks})

    for i, line in ipairs(lines) do
      local line_num = first_line + i - 1
      data.line_counts[line_num] = line_wordcount(line)

      local header_level = line:match(header_re)

      region = data.regions_by_line[line_num]

      if region then
        if header_level then
          region.level = #header_level
        else
          -- Remove the region
          delete_region(data, line_num)
        end
      elseif header_level then
          add_region(data, line_num, header_level)
      end
    end

    -- Remove line counts past the end of the file
    for i = buffer_line_count, table.maxn(data.line_counts) do
      data.line_counts[i] = nil
    end

    update_wordcounts(data, first_line, last_line)
    if line_diff ~= 0 then
      -- Neovim doesn't always update the headers when lines are added or removed, so force it.
      vim.schedule(function() vim.cmd("redraw!") end)
    end
  end


  handle_change(0, api.nvim_buf_line_count(0), api.nvim_buf_line_count(0))
  api.nvim_buf_attach(0, false, {
    on_lines = function(_, _, _, first_line, last_line, new_last_line)
      handle_change(first_line, last_line, new_last_line)
    end,
    on_reload = function()
      handle_change(0, api.nvim_buf_line_count(0), api.nvim_buf_line_count(0))
    end,
    on_detach = function()
      buffer_data[bufnr] = nil
      api.nvim_buf_clear_namespace(0, ns_id, 0, -1)
    end
  })
end


M.setup = function(options)
  option = options or {}
  highlight = api.nvim_get_hl_id_by_name(option.highlight or "String")
  virt_text_pos = option.virt_text_pos or "eol"
  ns_id = api.nvim_create_namespace("section-wordcount")

  api.nvim_set_decoration_provider(ns_id, {
    on_win = function(_, _, bufnr, winid)
      local data = buffer_data[bufnr]
      return data ~= nil
    end,
    on_line = function(_, _, bufnr, line)
      local data = buffer_data[bufnr]
      if data then
        local region = data.regions_by_line[line + 1]
        if region then
          api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
            ephemeral = true,
            -- Allow other virtual text to show above this.
            priority = 0,
            virt_text_pos = virt_text_pos,
            virt_text = { { region.virt_text, highlight } }
          })
        end
      end
    end,
  })

  -- api.nvim_command("augroup wordcounter")
  -- api.nvim_command("autocmd!")
  -- api.nvim_command("autocmd BufEnter * lua require'wordcounter'.wordcounter()")
  -- api.nvim_command("augroup END")
end

return M
