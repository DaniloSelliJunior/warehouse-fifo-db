-- =====================================================================
-- 04_rastreabilidade.sql - Historia completa de um lote
-- Caso de uso: o fornecedor fez recall de um lote. De onde veio,
-- onde ainda esta e para quais clientes ja foi vendido?
-- Uso: psql -d bd_deposito -f queries/04_rastreabilidade.sql -v lote=CIM-A1
-- =====================================================================
\if :{?lote}
\else
\set lote 'CIM-A1'
\endif

-- Origem
SELECT l.Codigo_lote, p.Descricao AS Produto, f.Razao_social AS Fornecedor,
       r.Numero_nf, r.Data_recebimento, l.Data_validade, l.Quantidade_recebida,
       fu.Nome_funcionario AS Conferente
  FROM LOTE l
  JOIN PRODUTO p      ON p.Id_produto = l.Id_produto
  JOIN RECEBIMENTO r  ON r.Id_recebimento = l.Id_recebimento
  JOIN FORNECEDOR f   ON f.Id_fornecedor = r.Id_fornecedor
  JOIN FUNCIONARIO fu ON fu.Id_funcionario = r.Id_funcionario
 WHERE l.Codigo_lote = :'lote';

-- Movimentacoes
SELECT Data_hora, Tipo, Codigo_endereco, Quantidade, Funcionario, Id_venda, Cliente
  FROM VW_EXTRATO_MOVIMENTACAO
 WHERE Codigo_lote = :'lote'
 ORDER BY Data_hora;

-- Onde ainda esta
SELECT Codigo_endereco, Zona, Quantidade, Situacao
  FROM VW_ESTOQUE_DETALHADO
 WHERE Codigo_lote = :'lote';
