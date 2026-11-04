-- =====================================================================
-- 04_dados_exemplo.sql - Carga de dados ficticios - PostgreSQL 16
--
-- Todas as datas sao relativas a CURRENT_DATE, entao o cenario e o mesmo
-- em qualquer dia em que o banco for criado:
--   * um lote de cimento VENCIDO ainda no endereco de picking (CIM-A1)
--   * um lote de cimento que VENCE EM 30 DIAS (CIM-A2)
--   * vendas atendidas pela regra FIFO + validade
-- Entradas e saidas usam as funcoes do 02_regras.sql, como faria o sistema.
-- Nomes, CNPJs e CPFs sao inventados.
-- =====================================================================

SET search_path TO estoque, public;
\o /dev/null

BEGIN;

-- ---------- Cadastros basicos ----------
INSERT INTO CATEGORIA (Id_categoria, Nome_categoria, Descricao_categoria) VALUES
 (1, 'Cimento e argamassa',          'Sacaria com validade curta'),
 (2, 'Tintas e solventes',           'Galoes e latas'),
 (3, 'Impermeabilizantes e rejuntes','Produtos quimicos de acabamento'),
 (4, 'Hidraulica',                   'Tubos e conexoes'),
 (5, 'Eletrica',                     'Cabos, disjuntores e acessorios'),
 (6, 'Ferragens e fixacao',          'Parafusos, buchas e pregos');

INSERT INTO PRODUTO (Id_produto, Sku, Descricao, Unidade, Peso_kg, Perecivel, Prazo_validade_dias, Id_categoria) VALUES
 ( 1, 'CIM-CPII-50', 'Cimento CP II 50 kg',              'SC', 50.00, 'S',   90, 1),
 ( 2, 'ARG-AC1-20',  'Argamassa AC-I 20 kg',             'SC', 20.00, 'S',  180, 1),
 ( 3, 'ARG-AC3-20',  'Argamassa AC-III 20 kg',           'SC', 20.00, 'S',  180, 1),
 ( 4, 'TIN-ACR-18',  'Tinta acrilica fosca branca 18 L', 'GL', 25.00, 'S', 1095, 2),
 ( 5, 'TIN-ESM-36',  'Esmalte sintetico 3,6 L',          'GL',  4.20, 'S', 1095, 2),
 ( 6, 'REJ-FLX-1',   'Rejunte flexivel 1 kg',            'PC',  1.00, 'S',  365, 3),
 ( 7, 'IMP-MAN-18',  'Manta liquida 18 kg',              'BD', 18.00, 'S',  365, 3),
 ( 8, 'TUB-PVC-25',  'Tubo PVC soldavel 25 mm 6 m',      'BR',  1.80, 'N', NULL, 4),
 ( 9, 'JOE-PVC-25',  'Joelho PVC 90 graus 25 mm',        'PC',  0.03, 'N', NULL, 4),
 (10, 'CAB-FLX-25',  'Cabo flexivel 2,5 mm rolo 100 m',  'RL',  3.00, 'N', NULL, 5),
 (11, 'DIS-BIP-20',  'Disjuntor bipolar 20 A',           'PC',  0.25, 'N', NULL, 5),
 (12, 'PAR-S8-100',  'Parafuso com bucha S8 (cx 100)',   'CX',  0.90, 'N', NULL, 6);

INSERT INTO FORNECEDOR (Id_fornecedor, Razao_social, Cnpj, Telefone, Cidade) VALUES
 (1, 'Cimentos Planalto Ltda',        '11.111.111/0001-11', '(16) 3000-0001', 'Ribeirao Preto'),
 (2, 'Tintas Aquarela S.A.',          '22.222.222/0001-22', '(11) 3000-0002', 'Sao Paulo'),
 (3, 'HidroFlex Conexoes Ltda',       '33.333.333/0001-33', '(19) 3000-0003', 'Campinas'),
 (4, 'Eletro Sul Distribuidora Ltda', '44.444.444/0001-44', '(16) 3000-0004', 'Araraquara');

INSERT INTO FUNCIONARIO (Id_funcionario, Nome_funcionario, Matricula, Cargo) VALUES
 (1, 'Ana Ribeiro',  'F001', 'Conferente'),
 (2, 'Bruno Costa',  'F002', 'Operador de empilhadeira'),
 (3, 'Carla Mendes', 'F003', 'Vendedora'),
 (4, 'Diego Alves',  'F004', 'Separador');

INSERT INTO CLIENTE (Id_cliente, Nome_cliente, Cpf_cnpj, Telefone_cliente, Cidade_cliente) VALUES
 (1, 'Construtora Horizonte Ltda', '55.555.555/0001-55', '(16) 99000-0001', 'Sao Carlos'),
 (2, 'Marcos Pereira',             '111.222.333-44',     '(16) 99000-0002', 'Sao Carlos'),
 (3, 'Reformas Rapidas ME',        '66.666.666/0001-66', '(16) 99000-0003', 'Ibate'),
 (4, 'Juliana Santos',             '555.666.777-88',     NULL,              'Sao Carlos');

-- ---------- Layout fisico do deposito ----------
INSERT INTO ZONA (Id_zona, Nome_zona, Local_fisico, Funcao) VALUES
 (1, 'Porta-pallet - reserva de sacaria', 'ESTOQUE',   'RESERVA'),
 (2, 'Piso - area de blocagem',           'ESTOQUE',   'RESERVA'),
 (3, 'Prateleiras - picking geral',       'ESTOQUE',   'PICKING'),
 (4, 'Mezanino - itens miudos',           'MEZANINO',  'PICKING'),
 (5, 'Expedicao - picking de sacaria',    'EXPEDICAO', 'PICKING');

-- ACEITA (M:N): categorias que cada zona pode guardar
INSERT INTO ZONA_CATEGORIA (Id_zona, Id_categoria) VALUES
 (1, 1), (1, 3),
 (2, 1), (2, 2), (2, 3),
 (3, 2), (3, 3), (3, 4), (3, 5), (3, 6),
 (4, 4), (4, 5), (4, 6),
 (5, 1);

-- Enderecos: Codigo = Corredor-Modulo-Nivel. Capacidade em unidades do produto.
-- Superclasse e subclasse na mesma transacao (especializacao total, gatilho adiado).
INSERT INTO ENDERECO (Id_endereco, Id_zona, Codigo_endereco, Corredor, Modulo, Nivel, Capacidade_max, Tipo_endereco, Ativo) VALUES
 ( 1, 1, 'A-01-1', 'A', 1, 1,  40, 'PP', 'S'),
 ( 2, 1, 'A-01-2', 'A', 1, 2,  40, 'PP', 'S'),
 ( 3, 1, 'A-02-1', 'A', 2, 1,  40, 'PP', 'S'),
 ( 4, 1, 'A-02-2', 'A', 2, 2,  40, 'PP', 'S'),
 ( 5, 2, 'P-01-0', 'P', 1, 0, 120, 'PI', 'S'),
 ( 6, 2, 'P-02-0', 'P', 2, 0, 120, 'PI', 'S'),
 ( 7, 3, 'B-01-1', 'B', 1, 1,  60, 'PR', 'S'),
 ( 8, 3, 'B-01-2', 'B', 1, 2,  60, 'PR', 'S'),
 ( 9, 3, 'B-02-1', 'B', 2, 1,  60, 'PR', 'S'),
 (10, 3, 'B-02-2', 'B', 2, 2,  60, 'PR', 'S'),
 (11, 4, 'M-01-1', 'M', 1, 1, 500, 'PR', 'S'),
 (12, 4, 'M-01-2', 'M', 1, 2, 500, 'PR', 'S'),
 (13, 4, 'M-02-1', 'M', 2, 1, 500, 'PR', 'N'),   -- em manutencao
 (14, 5, 'X-01-0', 'X', 1, 0,  30, 'PI', 'S');

INSERT INTO ENDERECO_PORTA_PALLET (Id_endereco, Altura_vao_m, Carga_max_kg) VALUES
 (1, 1.50, 1200), (2, 1.50, 1200), (3, 1.50, 1200), (4, 1.50, 1200);

INSERT INTO ENDERECO_PRATELEIRA (Id_endereco, Largura_m, Carga_nivel_kg) VALUES
 (7, 1.20, 150), (8, 1.20, 150), (9, 1.20, 150), (10, 1.20, 150),
 (11, 1.00, 80), (12, 1.00, 80), (13, 1.00, 80);

INSERT INTO ENDERECO_PISO (Id_endereco, Area_m2, Empilhamento_max) VALUES
 (5, 1.44, 10), (6, 1.44, 10), (14, 2.00, 6);

-- ---------- Recebimentos (notas fiscais) e lotes ----------
INSERT INTO RECEBIMENTO (Id_recebimento, Numero_nf, Data_recebimento, Id_fornecedor, Id_funcionario) VALUES
 (1, '000101', CURRENT_DATE - 60, 1, 1),
 (2, '000102', CURRENT_DATE - 20, 1, 1),
 (3, '5521',   CURRENT_DATE - 45, 2, 1),
 (4, '8890',   CURRENT_DATE - 30, 3, 1),
 (5, '3307',   CURRENT_DATE - 15, 4, 1),
 (6, '000117', CURRENT_DATE -  5, 1, 1);

INSERT INTO LOTE (Id_lote, Id_produto, Id_recebimento, Codigo_lote, Data_fabricacao, Data_validade, Quantidade_recebida) VALUES
 ( 1,  1, 1, 'CIM-A1',     CURRENT_DATE - 92, CURRENT_DATE -   2,  20),  -- vence 2 dias antes de hoje
 ( 2,  1, 1, 'CIM-A2',     CURRENT_DATE - 61, CURRENT_DATE +  29,  60),  -- vence em menos de 30 dias
 ( 3,  1, 2, 'CIM-B1',     CURRENT_DATE - 22, CURRENT_DATE +  68,  90),
 ( 4,  2, 2, 'ACI-0907',   CURRENT_DATE - 25, CURRENT_DATE + 155,  40),
 ( 5,  3, 6, 'ACIII-0001', CURRENT_DATE - 10, CURRENT_DATE + 170,  30),
 ( 6,  4, 3, 'TA-2310',    CURRENT_DATE - 50, CURRENT_DATE + 700,  36),
 ( 7,  4, 3, 'TA-2402',    CURRENT_DATE - 48, CURRENT_DATE + 900,  12),
 ( 8,  5, 3, 'ES-118',     CURRENT_DATE - 60, CURRENT_DATE + 500,  30),
 ( 9,  6, 6, 'RJ-55',      CURRENT_DATE - 30, CURRENT_DATE + 300, 100),
 (10,  7, 6, 'MN-12',      CURRENT_DATE - 40, CURRENT_DATE + 200,  10),
 (11,  8, 4, 'TB-0425',    NULL,              NULL,                50),
 (12,  9, 4, 'JO-0425',    NULL,              NULL,               300),
 (13, 10, 5, 'CB-77',      NULL,              NULL,                20),
 (14, 11, 5, 'DJ-31',      NULL,              NULL,                60),
 (15, 12, 5, 'PF-09',      NULL,              NULL,                40);

-- ---------- Entradas (enderecamento) ----------
-- Endereco NULL = usa o sugerido por fn_sugerir_endereco.
-- Parametros: lote, quantidade, funcionario, endereco, data/hora
-- D-60: cimento da NF 000101
SELECT fn_registrar_entrada( 1,  20, 2, 14,   CURRENT_DATE - 60 + TIME '09:00');  -- direto no picking da expedicao (sugestao era A-01-1)
SELECT fn_registrar_entrada( 2,  40, 2, NULL, CURRENT_DATE - 60 + TIME '09:20');  -- sugerido: A-01-1
SELECT fn_registrar_entrada( 2,  20, 2, NULL, CURRENT_DATE - 60 + TIME '09:30');  -- sugerido: A-01-2
-- D-45: tintas
SELECT fn_registrar_entrada( 6,  24, 2, NULL, CURRENT_DATE - 45 + TIME '14:00');  -- sugerido: P-01-0 (reserva)
SELECT fn_registrar_entrada( 6,  12, 4, 7,    CURRENT_DATE - 45 + TIME '14:20');  -- prateleira de picking
SELECT fn_registrar_entrada( 7,  12, 4, 8,    CURRENT_DATE - 45 + TIME '14:30');
SELECT fn_registrar_entrada( 8,  30, 4, 9,    CURRENT_DATE - 45 + TIME '14:40');
-- D-30: hidraulica
SELECT fn_registrar_entrada(11,  50, 4, 10,   CURRENT_DATE - 30 + TIME '11:00');
SELECT fn_registrar_entrada(12, 300, 4, NULL, CURRENT_DATE - 30 + TIME '11:20');  -- sugerido: M-01-1 (mezanino)
-- D-20: cimento e argamassa da NF 000102
SELECT fn_registrar_entrada( 3,  80, 2, NULL, CURRENT_DATE - 20 + TIME '10:00');  -- sugerido: P-01-0
SELECT fn_registrar_entrada( 3,  10, 2, 14,   CURRENT_DATE - 20 + TIME '10:15');  -- completa o picking
SELECT fn_registrar_entrada( 4,  40, 2, NULL, CURRENT_DATE - 20 + TIME '10:30');  -- sugerido: A-02-1
-- D-15: eletrica e ferragens
SELECT fn_registrar_entrada(13,  20, 4, 12,   CURRENT_DATE - 15 + TIME '15:00');
SELECT fn_registrar_entrada(14,  60, 4, 12,   CURRENT_DATE - 15 + TIME '15:10');
SELECT fn_registrar_entrada(15,  40, 4, 11,   CURRENT_DATE - 15 + TIME '15:20');
-- D-5: NF 000117
SELECT fn_registrar_entrada( 5,  30, 2, 4,    CURRENT_DATE -  5 + TIME '08:40');
SELECT fn_registrar_entrada( 9, 100, 2, NULL, CURRENT_DATE -  5 + TIME '09:00');  -- sugerido: P-02-0
SELECT fn_registrar_entrada(10,  10, 4, 10,   CURRENT_DATE -  5 + TIME '09:30');

-- ---------- Vendas e saidas FIFO ----------
INSERT INTO VENDA (Id_venda, Data_venda, Id_cliente, Id_funcionario) VALUES
 (1, CURRENT_DATE - 3, 1, 3),
 (2, CURRENT_DATE - 1, 2, 3),
 (3, CURRENT_DATE,     3, 3);

INSERT INTO ITEM_VENDA (Id_item_venda, Id_venda, Id_produto, Quantidade_item, Preco_unitario) VALUES
 (1, 1,  1, 12,  38.90),   -- cimento: 3 dias atras o lote CIM-A1 ainda valia -> sai dele
 (2, 1,  2, 10,  24.50),
 (3, 1,  8, 12,  32.00),
 (4, 2,  4,  2, 289.90),   -- tinta: lote TA-2310 (vence antes), prateleira de picking primeiro
 (5, 2,  6,  8,  12.90),
 (6, 2,  9, 20,   2.10),
 (7, 3,  1, 15,  38.90),   -- cimento hoje: CIM-A1 venceu -> pula para CIM-A2
 (8, 3, 11,  4,  29.90),
 (9, 3, 12,  3,  18.50);

SELECT * FROM fn_registrar_saida_fifo(1, 4, CURRENT_DATE - 3 + TIME '16:00');
SELECT * FROM fn_registrar_saida_fifo(2, 4, CURRENT_DATE - 3 + TIME '16:05');
SELECT * FROM fn_registrar_saida_fifo(3, 4, CURRENT_DATE - 3 + TIME '16:10');
SELECT * FROM fn_registrar_saida_fifo(4, 4, CURRENT_DATE - 1 + TIME '10:00');
SELECT * FROM fn_registrar_saida_fifo(5, 4, CURRENT_DATE - 1 + TIME '10:05');
SELECT * FROM fn_registrar_saida_fifo(6, 4, CURRENT_DATE - 1 + TIME '10:10');
SELECT * FROM fn_registrar_saida_fifo(7, 4, CURRENT_DATE     + TIME '00:01');
SELECT * FROM fn_registrar_saida_fifo(8, 4, CURRENT_DATE     + TIME '00:02');
SELECT * FROM fn_registrar_saida_fifo(9, 4, CURRENT_DATE     + TIME '00:03');

-- ---------- Ajusta as sequencias das chaves IDENTITY ----------
-- (os cadastros acima usaram Id explicito; o proximo INSERT sem Id continua do maximo)
DO $$
DECLARE
    c RECORD;
BEGIN
    FOR c IN
        SELECT table_name, column_name
          FROM information_schema.columns
         WHERE table_schema = 'estoque' AND is_identity = 'YES'
    LOOP
        EXECUTE format(
            'SELECT setval(pg_get_serial_sequence(%L, %L), COALESCE((SELECT MAX(%I) FROM estoque.%I), 0) + 1, false)',
            'estoque.' || c.table_name, c.column_name, c.column_name, c.table_name);
    END LOOP;
END $$;

COMMIT;
\o
