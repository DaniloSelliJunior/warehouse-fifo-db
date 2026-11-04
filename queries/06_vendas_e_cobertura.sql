-- =====================================================================
-- 06_vendas_e_cobertura.sql - Vendas por produto e dias de cobertura
-- Cobertura = saldo valido / media diaria vendida nos ultimos N dias.
-- Uso: psql -d bd_deposito -f queries/06_vendas_e_cobertura.sql -v dias=30
-- =====================================================================
\if :{?dias}
\else
\set dias 30
\endif

WITH vendido AS (
    SELECT iv.Id_produto,
           SUM(iv.Quantidade_item)                         AS Qtd_vendida,
           SUM(iv.Quantidade_item * iv.Preco_unitario)     AS Faturamento
      FROM ITEM_VENDA iv
      JOIN VENDA v ON v.Id_venda = iv.Id_venda
     WHERE v.Data_venda > CURRENT_DATE - :dias
     GROUP BY iv.Id_produto
)
SELECT s.Sku, s.Produto,
       COALESCE(v.Qtd_vendida, 0)                          AS Vendido_no_periodo,
       COALESCE(v.Faturamento, 0)                          AS Faturamento,
       s.Saldo_valido,
       CASE WHEN COALESCE(v.Qtd_vendida, 0) = 0 THEN NULL
            ELSE ROUND(s.Saldo_valido / (v.Qtd_vendida::NUMERIC / :dias), 0)
       END                                                 AS Dias_de_cobertura
  FROM VW_SALDO_PRODUTO s
  LEFT JOIN vendido v ON v.Id_produto = s.Id_produto
 ORDER BY Faturamento DESC, s.Sku;
