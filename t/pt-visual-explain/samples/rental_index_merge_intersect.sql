mysql> explain select * from sakila.rental where customer_id = 130 and inventory_id = 3009\G
*************************** 1. row ***************************
           id: 1
  select_type: SIMPLE
        table: rental
         type: index_merge
possible_keys: idx_fk_inventory_id,idx_fk_customer_id
          key: idx_fk_inventory_id,idx_fk_customer_id
      key_len: 3,2
          ref: NULL
         rows: 1
        Extra: Using intersect(idx_fk_inventory_id,idx_fk_customer_id); Using where
1 row in set (0.00 sec)

mysql> notee
