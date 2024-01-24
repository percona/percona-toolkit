/* Prepare two statements*/

SET @random_statement_prepare = 'SELECT RAND() AS rand';
PREPARE rand_statement FROM @random_statement_prepare;

SET @absolute_value_statement_prepare = 'SELECT ABS(?) AS abs_A';
PREPARE abs_statement FROM @absolute_value_statement_prepare;

/* Wait to let pt-stalk to collect the data and find these prepare  statements */
SELECT SLEEP(11);

