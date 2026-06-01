-- [[ user.llm.config ]]
-- Configure local LLM providers here. Model refs use "provider/model".

local M = {
  providers = {
    ollama = {
      kind = 'ollama',
      base_url = 'http://127.0.0.1:11434/',
    },
    ds4 = {
      kind = 'openai',
      base_url = 'http://127.0.0.1:8000/v1',
    },
  },
  models = {
    translate = 'ollama/translategemma:4b',
    ask = 'ollama/gemma4:31b',
  },
}

return M
