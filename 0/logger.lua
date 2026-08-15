-- logger.lua
-- Модуль для логирования в терминал и в чат-бокс

local Logger = {}
local chatBox = peripheral.wrap("chat_box_0")  -- предполагаем, что чат-бокс называется так

function Logger.log(...)
    local old = term.current()
    term.redirect(term.native())
    print(...)
    term.redirect(old)

    if chatBox then
        local msg = ""
        for i = 1, select('#', ...) do
            msg = msg .. tostring(select(i, ...)) .. " "
        end
        chatBox.sendMessage(msg)
    end
end

-- Можно также добавить уровень важности, но пока так
return Logger