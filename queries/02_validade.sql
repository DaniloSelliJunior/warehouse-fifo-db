-- =====================================================================
-- 02_validade.sql - Lotes vencidos e que vencem nos proximos N dias
-- Vencidos devem ser retirados do endereco; os proximos de vencer
-- podem ganhar prioridade de venda (promocao).
-- Uso: psql -d bd_deposito -f queries/02_validade.sql -v dias=60
-- =====================================================================
\if :{?dias}
\else
\set dias 30
\endif

SELECT Situacao, Produto, Codigo_lote, Data_validade, Dias_para_vencer,
       Zona, Codigo_endereco, Quantidade, Unidade
  FROM VW_ESTOQUE_DETALHADO
 WHERE Data_validade <= CURRENT_DATE + :dias
 ORDER BY Data_validade, Codigo_endereco;
