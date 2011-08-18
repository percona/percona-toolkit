#!/bin/bash

TESTS=2

cat <<EOF > $TMPDIR/expected

  Database Tables Views SPs Trigs Funcs   FKs Partn
  mysql        17                                  
  sakila       17     7   3     6     3    22     1

  Database MyISAM InnoDB
  mysql        17       
  sakila        2     15

  Database BTREE FULLTEXT
  mysql       24         
  sakila      63        1

             c   t   s   e   t   s   i   t   b   l   b   v   d   y   d   m
             h   i   e   n   i   m   n   e   l   o   i   a   a   e   e   e
             a   m   t   u   n   a   t   x   o   n   g   r   t   a   c   d
             r   e       m   y   l       t   b   g   i   c   e   r   i   i
                 s           i   l               b   n   h   t       m   u
                 t           n   i               l   t   a   i       a   m
                 a           t   n               o       r   m       l   i
                 m               t               b           e           n
                 p                                                       t
  Database === === === === === === === === === === === === === === === ===
  mysql     38   5   5  69   2   3  16   2   4   1   2                    
  sakila     1  15   1   3  19  26   3   4   1          45   4   1   7   2

EOF
format_overall_db_stats samples/mysql-schema-001.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected


cat <<EOF > $TMPDIR/expected

  Database Tables Views SPs Trigs Funcs   FKs Partn
  {chosen}      1                                  

  Database InnoDB
  {chosen}      1

  Database BTREE
  {chosen}     2

             t   v
             i   a
             n   r
             y   c
             i   h
             n   a
             t   r
  Database === ===
  {chosen}   1   1

EOF
format_overall_db_stats samples/mysql-schema-002.txt > $TMPDIR/got
no_diff $TMPDIR/got $TMPDIR/expected
