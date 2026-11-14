# Приватная часть: llm-gateway · Владелец: modules/ai/llm-gateway.nix (STR-6)
# Чистая функция: цены моделей из политики хоста (`my.ai.gateway.providers.<id>.prices`,
# USD за 1M токенов) → справочник цен Bifrost (формат getbifrost.ai/datasheet: ключ
# `<тип>/<модель>`, цена за токен). По нему шлюз считает расход и бюджеты (AI-GW-6, ADR-49);
# справочник поставщика шлюза больше не скачивается (AI-GW-13). Причина (D24): в справочнике
# поставщика DeepSeek стоит по пиковому тарифу, а скидку вне пика (−50 %) Bifrost 2.1.0 не
# знает — счётчик выходил вдвое выше списаний провайдера и бюджет закрывался на половине.
# Стоимость запроса у шлюза: вход без кэша × input + вход из кэша × cacheRead + выход × output
# (сверено 2026-11-14 по журналам dsh: $9.99 против счётчика $10.0033). Запись в кэш DeepSeek
# не тарифицирует — 0.
{ lib }:
{ providers }:
let
  perToken = usdPerMillion: usdPerMillion / 1000000.0;
in
lib.listToAttrs (
  lib.concatLists (
    lib.mapAttrsToList (
      _: p:
      lib.mapAttrsToList (model: price: {
        name = "${p.type}/${model}";
        value = {
          provider = p.type;
          mode = "chat";
          base_model = model;
          input_cost_per_token = perToken price.input;
          output_cost_per_token = perToken price.output;
          cache_read_input_token_cost = perToken price.cacheRead;
          input_cost_per_token_cache_hit = perToken price.cacheRead;
          cache_creation_input_token_cost = 0;
        };
      }) p.prices
    ) providers
  )
)
