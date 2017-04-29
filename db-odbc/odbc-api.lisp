;;;; -*- Mode: LISP; Syntax: ANSI-Common-Lisp; Package: odbc -*-
;;;; *************************************************************************
;;;; FILE IDENTIFICATION
;;;;
;;;; Name:     odbc-api.lisp
;;;; Purpose:  Low-level ODBC API using UFFI
;;;; Authors:  Kevin M. Rosenberg and Paul Meurer
;;;;
;;;; This file, part of CLSQL, is Copyright (c) 2004 by Kevin M. Rosenberg
;;;; and Copyright (C) Paul Meurer 1999 - 2001. All rights reserved.
;;;;
;;;; CLSQL users are granted the rights to distribute and use this software
;;;; as governed by the terms of the Lisp Lesser GNU Public License
;;;; (http://opensource.franz.com/preamble.html), also known as the LLGPL.
;;;; *************************************************************************

(in-package #:odbc)

(defvar *null* nil
  "Lisp representation of SQL Null value, default = nil.
May be locally bound to something else if a certain type is necessary.")


(defvar *binary-format* :unsigned-byte-vector)
(defvar *time-format*
  (lambda (time)
    (clsql-sys:format-time nil time :format :iso))
   "Bound to a function that converts from a clsql:wall-time to the desired
    representation of date/time/timestamp.
    By default, returns an iso-timestring.")

(defvar +null-ptr+ (make-null-pointer :byte))
(defparameter +null-handle-ptr+ (make-null-pointer :void))
(defvar *info-output* nil
  "Stream to send SUCCESS_WITH_INFO messages.")

(defmacro %put-str (ptr string &optional max-length)
  (let ((size (gensym)))
    `(let ((,size (length ,string)))
       (when (and ,max-length (> ,size ,max-length))
         (error 'clsql:sql-database-data-error
                :message
                (format nil "string \"~a\" of length ~d is longer than max-length: ~d"
                        ,string ,size ,max-length)))
      (with-cast-pointer (char-ptr ,ptr :byte)
        (dotimes (i ,size)
          (setf (deref-array char-ptr '(:array :byte) i)
                (char-code (char ,string i))))
        (setf (deref-array char-ptr '(:array :byte) ,size) 0)))))

(defmacro with-allocate-foreign-string ((var len) &body body)
  "Safely does uffi:allocate-foreign-string-- making sure we do the uffi:free-foreign-object"
  `(let ((,var))
    (unwind-protect
         (progn
           (setf ,var (uffi:allocate-foreign-string ,len))
           ,@body)
      (when ,var
        (uffi:free-foreign-object ,var)))))

(defmacro with-allocate-foreign-strings (bindings &rest body)
  (if bindings
      `(with-allocate-foreign-string ,(car bindings)
        (with-allocate-foreign-strings ,(cdr bindings)
          ,@body))
      `(progn ,@body)))

(defun handle-error (henv hdbc hstmt)
  (with-allocate-foreign-strings ((sql-state 256)
                                  (error-message #.$SQL_MAX_MESSAGE_LENGTH))
   (with-foreign-objects ((error-code #.$ODBC-LONG-TYPE)
                          (msg-length :short))
    (SQLError henv hdbc hstmt sql-state
              error-code error-message
              #.$SQL_MAX_MESSAGE_LENGTH msg-length)
    (values
     (convert-from-foreign-string error-message)
     (convert-from-foreign-string sql-state)
     (deref-pointer msg-length :short)
     (deref-pointer error-code #.$ODBC-LONG-TYPE)))))

(defun sql-state (henv hdbc hstmt)
  (with-allocate-foreign-strings ((sql-state 256)
                                  (error-message #.$SQL_MAX_MESSAGE_LENGTH))
   (with-foreign-objects ((error-code #.$ODBC-LONG-TYPE)
                          (msg-length :short))
    (SQLError henv hdbc hstmt sql-state error-code
              error-message #.$SQL_MAX_MESSAGE_LENGTH msg-length)
    (convert-from-foreign-string sql-state)
    ;; test this: return a keyword for efficiency
    ;;(%cstring-to-keyword state)
    )))

(defmacro with-error-handling ((&key henv hdbc hstmt (print-info t))
                                   odbc-call &body body)
  (let ((result-code (gensym "RC-")))
    `(let ((,result-code ,odbc-call))

      ;; Check for allegro v7 & v8 bug with ODBC calls returning
      ;; 32-bit unsigned ints, not 16-bit signed ints
      #+(and allegro mswindows)
      (when (> ,result-code #xFFFF)
        (warn (format nil "16-bit return bug: result-code #x~X for expression ~S"
                      ,result-code (quote ,odbc-call)))
        (setq ,result-code (logand ,result-code #xFFFF))
        (when (> ,result-code #x7FFF)
          (setq ,result-code (- ,result-code #x10000))))

       (case ,result-code
         (#.$SQL_SUCCESS
          (progn ,result-code ,@body))
         (#.$SQL_SUCCESS_WITH_INFO
          (when ,print-info
            (multiple-value-bind (error-message sql-state)
                (handle-error (or ,henv +null-handle-ptr+)
                              (or ,hdbc +null-handle-ptr+)
                              (or ,hstmt +null-handle-ptr+))
              (when *info-output*
                (format *info-output* "[ODBC info ~A] ~A state: ~A"
                        ,result-code error-message
                        sql-state))))
          (progn ,result-code ,@body))
         (#.$SQL_INVALID_HANDLE
          (error
           'clsql-sys:sql-database-error
           :message "ODBC: Invalid handle"))
         (#.$SQL_STILL_EXECUTING
          (error
           'clsql-sys:sql-temporary-error
           :message "ODBC: Still executing"))
         (#.$SQL_ERROR
          (multiple-value-bind (error-message sql-state)
              (handle-error (or ,henv +null-handle-ptr+)
                            (or ,hdbc +null-handle-ptr+)
                            (or ,hstmt +null-handle-ptr+))
            (error
             'clsql-sys:sql-database-error
             :message error-message
             :secondary-error-id sql-state)))
         (#.$SQL_NO_DATA_FOUND
          (progn ,result-code ,@body))
         ;; work-around for Allegro 7.0beta AMD64 which returns negative numbers
         (otherwise
          (multiple-value-bind (error-message sql-state)
              (handle-error (or ,henv +null-handle-ptr+)
                            (or ,hdbc +null-handle-ptr+)
                            (or ,hstmt +null-handle-ptr+))
            (error
             'clsql-sys:sql-database-error
             :message error-message
             :secondary-error-id sql-state))
          #+ignore
          (progn ,result-code ,@body))))))

(defun %new-environment-handle ()
  (let ((henv
         (with-foreign-object (phenv 'sql-handle)
           (with-error-handling
               ()
             (SQLAllocHandle $SQL_HANDLE_ENV +null-handle-ptr+ phenv)
             (deref-pointer phenv 'sql-handle)))))
    (%set-attr-odbc-version henv $SQL_OV_ODBC3)
    henv))


(defun %sql-free-environment (henv)
  (with-error-handling
    (:henv henv)
    (SQLFreeEnv henv)))

(defun %new-db-connection-handle (henv)
  (with-foreign-object (phdbc 'sql-handle)
    (setf (deref-pointer phdbc 'sql-handle) +null-handle-ptr+)
    (with-error-handling
      (:henv henv)
      (SQLAllocHandle $SQL_HANDLE_DBC henv phdbc)
      (deref-pointer phdbc 'sql-handle))))

(defun %free-statement (hstmt option)
  (with-error-handling
      (:hstmt hstmt)
      (SQLFreeStmt
       hstmt
       (ecase option
         (:drop $SQL_DROP)
         (:close $SQL_CLOSE)
         (:unbind $SQL_UNBIND)
         (:reset $SQL_RESET_PARAMS)))))

(defmacro with-statement-handle ((hstmt hdbc) &body body)
  `(let ((,hstmt (%new-statement-handle ,hdbc)))
     (unwind-protect
       (progn ,@body)
       (%free-statement ,hstmt :drop))))

;; functional interface

(defun %sql-connect (hdbc server uid pwd)
  (with-cstrings ((server-ptr server)
                  (uid-ptr uid)
                  (pwd-ptr pwd))
    (with-error-handling
        (:hdbc hdbc)
      (SQLConnect hdbc server-ptr $SQL_NTS uid-ptr
                  $SQL_NTS pwd-ptr $SQL_NTS))))

(defun %sql-driver-connect (hdbc connection-string completion window-handle)
  (with-cstring (connection-ptr connection-string)
    (with-allocate-foreign-string (completed-connection-string-ptr $SQL_MAX_CONN_OUT)
      (with-foreign-object (completed-connection-length :short)
       (with-error-handling
           (:hdbc hdbc)
           (SQLDriverConnect hdbc
                             (or window-handle
                                 +null-handle-ptr+)
                             connection-ptr $SQL_NTS
                             completed-connection-string-ptr $SQL_MAX_CONN_OUT
                             completed-connection-length
                             completion))))))

(defun %disconnect (hdbc)
  (with-error-handling
    (:hdbc hdbc)
    (SQLDisconnect hdbc)
    (with-error-handling
        (:hdbc hdbc)
        (SQLFreeHandle $SQL_HANDLE_DBC hdbc))))

(defun %commit (henv hdbc)
  (with-error-handling
    (:henv henv :hdbc hdbc)
    (SQLTransact
     henv hdbc $SQL_COMMIT)))

(defun %rollback (henv hdbc)
  (with-error-handling
    (:henv henv :hdbc hdbc)
    (SQLTransact
     henv hdbc $SQL_ROLLBACK)))

; col-nr is zero-based in Lisp but 1 based in sql
; col-nr = :bookmark retrieves a bookmark.
(defun %bind-column (hstmt column-nr c-type data-ptr precision out-len-ptr)
  (with-error-handling
    (:hstmt hstmt)
    (SQLBindCol hstmt
                (if (eq column-nr :bookmark) 0 (1+ column-nr))
                c-type data-ptr precision out-len-ptr)))

; parameter-nr is zero-based in Lisp
(defun %sql-bind-parameter (hstmt parameter-nr parameter-type c-type
                                      sql-type precision scale data-ptr
                                      max-value out-len-ptr)
  (with-error-handling
    (:hstmt hstmt)
    (SQLBindParameter hstmt (1+ parameter-nr)
                      parameter-type ;$SQL_PARAM_INPUT
                      c-type ;$SQL_C_CHAR
                      sql-type ;$SQL_VARCHAR
                      precision ;(1- (length str))
                      scale ;0
                      data-ptr
                      max-value
                      out-len-ptr ;#.+null-ptr+
                      )))

(defun %sql-fetch (hstmt)
  (with-error-handling
      (:hstmt hstmt)
      (SQLFetch hstmt)))

(defun %new-statement-handle (hdbc)
  (let ((statement-handle
         (with-foreign-object (phstmt 'sql-handle)
           (with-error-handling
               (:hdbc hdbc)
             (SQLAllocHandle $SQL_HANDLE_STMT hdbc phstmt)
             (deref-pointer phstmt 'sql-handle)))))
    (if (uffi:null-pointer-p statement-handle)
        (error 'clsql:sql-database-error :message "Received null statement handle.")
        statement-handle)))

(defun %sql-get-info (hdbc info-type)
  (ecase info-type
    ;; those return string
    ((#.$SQL_ACCESSIBLE_PROCEDURES
      #.$SQL_ACCESSIBLE_TABLES
      #.$SQL_COLUMN_ALIAS
      #.$SQL_DATA_SOURCE_NAME
      #.$SQL_DATA_SOURCE_READ_ONLY
      #.$SQL_DBMS_NAME
      #.$SQL_DBMS_VER
      #.$SQL_DRIVER_NAME
      #.$SQL_DRIVER_ODBC_VER
      #.$SQL_DRIVER_VER
      #.$SQL_EXPRESSIONS_IN_ORDERBY
      #.$SQL_IDENTIFIER_QUOTE_CHAR
      #.$SQL_KEYWORDS
      #.$SQL_LIKE_ESCAPE_CLAUSE
      #.$SQL_MAX_ROW_SIZE_INCLUDES_LONG
      #.$SQL_MULT_RESULT_SETS
      #.$SQL_MULTIPLE_ACTIVE_TXN
      #.$SQL_NEED_LONG_DATA_LEN
      #.$SQL_ODBC_SQL_OPT_IEF
      #.$SQL_ODBC_VER
      #.$SQL_ORDER_BY_COLUMNS_IN_SELECT
      #.$SQL_OUTER_JOINS
      #.$SQL_OWNER_TERM
      #.$SQL_PROCEDURE_TERM
      #.$SQL_PROCEDURES
      #.$SQL_QUALIFIER_NAME_SEPARATOR
      #.$SQL_QUALIFIER_TERM
      #.$SQL_ROW_UPDATES
      #.$SQL_SEARCH_PATTERN_ESCAPE
      #.$SQL_SERVER_NAME
      #.$SQL_SPECIAL_CHARACTERS
      #.$SQL_TABLE_TERM
      #.$SQL_USER_NAME)
     (with-allocate-foreign-string (info-ptr 1024)
       (with-foreign-object (info-length-ptr :short)
        (with-error-handling
            (:hdbc hdbc)
            (SQLGetInfo hdbc info-type info-ptr 1023 info-length-ptr)
          (convert-from-foreign-string info-ptr)))))
    ;; those returning a word
    ((#.$SQL_ACTIVE_CONNECTIONS
      #.$SQL_ACTIVE_STATEMENTS
      #.$SQL_CONCAT_NULL_BEHAVIOR
      #.$SQL_CORRELATION_NAME
      #.$SQL_CURSOR_COMMIT_BEHAVIOR
      #.$SQL_CURSOR_ROLLBACK_BEHAVIOR
      #.$SQL_MAX_COLUMN_NAME_LEN
      #.$SQL_MAX_COLUMNS_IN_GROUP_BY
      #.$SQL_MAX_COLUMNS_IN_INDEX
      #.$SQL_MAX_COLUMNS_IN_ORDER_BY
      #.$SQL_MAX_COLUMNS_IN_SELECT
      #.$SQL_MAX_COLUMNS_IN_TABLE
      #.$SQL_MAX_CURSOR_NAME_LEN
      #.$SQL_MAX_OWNER_NAME_LEN
      #.$SQL_MAX_PROCEDURE_NAME_LEN
      #.$SQL_MAX_QUALIFIER_NAME_LEN
      #.$SQL_MAX_TABLE_NAME_LEN
      #.$SQL_MAX_TABLES_IN_SELECT
      #.$SQL_MAX_USER_NAME_LEN
      #.$SQL_NON_NULLABLE_COLUMNS
      #.$SQL_NULL_COLLATION
      #.$SQL_ODBC_API_CONFORMANCE
      #.$SQL_ODBC_SAG_CLI_CONFORMANCE
      #.$SQL_ODBC_SQL_CONFORMANCE
      #.$SQL_QUALIFIER_LOCATION
      #.$SQL_QUOTED_IDENTIFIER_CASE
      #.$SQL_TXN_CAPABLE)
     (with-foreign-objects ((info-ptr :short)
                            (info-length-ptr :short))
       (with-error-handling
        (:hdbc hdbc)
         (SQLGetInfo hdbc
                     info-type
                     info-ptr
                     255
                     info-length-ptr)
         (deref-pointer info-ptr :short)))
     )
    ;; those returning a long bitmask
    ((#.$SQL_ALTER_TABLE
      #.$SQL_BOOKMARK_PERSISTENCE
      #.$SQL_CONVERT_BIGINT
      #.$SQL_CONVERT_BINARY
      #.$SQL_CONVERT_BIT
      #.$SQL_CONVERT_CHAR
      #.$SQL_CONVERT_DATE
      #.$SQL_CONVERT_DECIMAL
      #.$SQL_CONVERT_DOUBLE
      #.$SQL_CONVERT_FLOAT
      #.$SQL_CONVERT_INTEGER
      #.$SQL_CONVERT_LONGVARCHAR
      #.$SQL_CONVERT_NUMERIC
      #.$SQL_CONVERT_REAL
      #.$SQL_CONVERT_SMALLINT
      #.$SQL_CONVERT_TIME
      #.$SQL_CONVERT_TIMESTAMP
      #.$SQL_CONVERT_TINYINT
      #.$SQL_CONVERT_VARBINARY
      #.$SQL_CONVERT_VARCHAR
      #.$SQL_CONVERT_LONGVARBINARY
      #.$SQL_CONVERT_FUNCTIONS
      #.$SQL_FETCH_DIRECTION
      #.$SQL_FILE_USAGE
      #.$SQL_GETDATA_EXTENSIONS
      #.$SQL_LOCK_TYPES
      #.$SQL_MAX_INDEX_SIZE
      #.$SQL_MAX_ROW_SIZE
      #.$SQL_MAX_STATEMENT_LEN
      #.$SQL_NUMERIC_FUNCTIONS
      #.$SQL_OWNER_USAGE
      #.$SQL_POS_OPERATIONS
      #.$SQL_POSITIONED_STATEMENTS
      #.$SQL_QUALIFIER_USAGE
      #.$SQL_SCROLL_CONCURRENCY
      #.$SQL_SCROLL_OPTIONS
      #.$SQL_STATIC_SENSITIVITY
      #.$SQL_STRING_FUNCTIONS
      #.$SQL_SUBQUERIES
      #.$SQL_SYSTEM_FUNCTIONS
      #.$SQL_TIMEDATE_ADD_INTERVALS
      #.$SQL_TIMEDATE_DIFF_INTERVALS
      #.$SQL_TIMEDATE_FUNCTIONS
      #.$SQL_TXN_ISOLATION_OPTION
      #.$SQL_UNION)
     (with-foreign-objects ((info-ptr #.$ODBC-LONG-TYPE)
                            (info-length-ptr :short))
       (with-error-handling
         (:hdbc hdbc)
         (SQLGetInfo hdbc
                     info-type
                     info-ptr
                     255
                     info-length-ptr)
         (deref-pointer info-ptr #.$ODBC-LONG-TYPE)))
     )
    ;; those returning a long integer
    ((#.$SQL_DEFAULT_TXN_ISOLATION
      #.$SQL_DRIVER_HDBC
      #.$SQL_DRIVER_HENV
      #.$SQL_DRIVER_HLIB
      #.$SQL_DRIVER_HSTMT
      #.$SQL_GROUP_BY
      #.$SQL_IDENTIFIER_CASE
      #.$SQL_MAX_BINARY_LITERAL_LEN
      #.$SQL_MAX_CHAR_LITERAL_LEN
      #.$SQL_ACTIVE_ENVIRONMENTS
      )
     (with-foreign-objects ((info-ptr #.$ODBC-LONG-TYPE)
                            (info-length-ptr :short))
       (with-error-handling
         (:hdbc hdbc)
         (SQLGetInfo hdbc info-type info-ptr 255 info-length-ptr)
         (deref-pointer info-ptr #.$ODBC-LONG-TYPE))))))

(defun %sql-exec-direct (sql hstmt henv hdbc)
  (with-cstring (sql-ptr sql)
    (with-error-handling
      (:hstmt hstmt :henv henv :hdbc hdbc)
      (SQLExecDirect hstmt sql-ptr $SQL_NTS))))

(defun %sql-cancel (hstmt)
  (with-error-handling
    (:hstmt hstmt)
    (SQLCancel hstmt)))

(defun %sql-execute (hstmt)
  (with-error-handling
    (:hstmt hstmt)
    (SQLExecute hstmt)))

(defun result-columns-count (hstmt)
  (with-foreign-objects ((columns-nr-ptr :short))
    (with-error-handling (:hstmt hstmt)
                         (SQLNumResultCols hstmt columns-nr-ptr)
      (deref-pointer columns-nr-ptr :short))))

(defun result-rows-count (hstmt)
  (with-foreign-objects ((row-count-ptr #.$ODBC-SQLLEN-TYPE))
    (with-error-handling (:hstmt hstmt)
                         (SQLRowCount hstmt row-count-ptr)
      (deref-pointer row-count-ptr #.$ODBC-SQLLEN-TYPE))))

;; column counting is 1-based
(defun %describe-column (hstmt column-nr)
  (with-allocate-foreign-string (column-name-ptr 256)
    (with-foreign-objects ((column-name-length-ptr :short)
                           (column-sql-type-ptr :short)
                           (column-precision-ptr #.$ODBC-SQLULEN-TYPE)
                           (column-scale-ptr :short)
                           (column-nullable-p-ptr :short))
     (with-error-handling (:hstmt hstmt)
         (SQLDescribeCol hstmt column-nr column-name-ptr 256
                         column-name-length-ptr
                         column-sql-type-ptr
                         column-precision-ptr
                         column-scale-ptr
                         column-nullable-p-ptr)
       (values
        (convert-from-foreign-string column-name-ptr)
        (deref-pointer column-sql-type-ptr :short)
        (deref-pointer column-precision-ptr #.$ODBC-SQLULEN-TYPE)
        (deref-pointer column-scale-ptr :short)
        (deref-pointer column-nullable-p-ptr :short))))))

;; parameter counting is 1-based
;; this function isn't used, which is good because FreeTDS dosn't support it.
(defun %describe-parameter (hstmt parameter-nr)
  (with-foreign-objects ((column-sql-type-ptr :short)
                         (column-precision-ptr #.$ODBC-ULONG-TYPE)
                         (column-scale-ptr :short)
                         (column-nullable-p-ptr :short))
    (with-error-handling
      (:hstmt hstmt)
      (SQLDescribeParam hstmt parameter-nr
                        column-sql-type-ptr
                        column-precision-ptr
                        column-scale-ptr
                        column-nullable-p-ptr)
      (values
       (deref-pointer column-sql-type-ptr :short)
       (deref-pointer column-precision-ptr #.$ODBC-ULONG-TYPE)
       (deref-pointer column-scale-ptr :short)
       (deref-pointer column-nullable-p-ptr :short)))))

(defun %column-attributes (hstmt column-nr descriptor-type)
  (with-allocate-foreign-string (descriptor-info-ptr 256)
    (with-foreign-objects ((descriptor-length-ptr :short)
                           (numeric-descriptor-ptr #.$ODBC-LONG-TYPE))
     (with-error-handling
         (:hstmt hstmt)
         (SQLColAttributes hstmt column-nr descriptor-type descriptor-info-ptr
                           256 descriptor-length-ptr
                           numeric-descriptor-ptr)
       (values
        (convert-from-foreign-string descriptor-info-ptr)
        (deref-pointer numeric-descriptor-ptr #.$ODBC-LONG-TYPE))))))

(defun %prepare-describe-columns (hstmt table-qualifier table-owner
                                   table-name column-name)
  (with-cstrings ((table-qualifier-ptr table-qualifier)
                  (table-owner-ptr table-owner)
                  (table-name-ptr table-name)
                  (column-name-ptr column-name))
    (with-error-handling
        (:hstmt hstmt)
      (SQLColumns hstmt
                  table-qualifier-ptr (length table-qualifier)
                  table-owner-ptr (length table-owner)
                  table-name-ptr (length table-name)
                  column-name-ptr (length column-name)))))

(defun %describe-columns (hdbc table-qualifier table-owner
                          table-name column-name)
  (with-statement-handle (hstmt hdbc)
    (%prepare-describe-columns hstmt table-qualifier table-owner
                               table-name column-name)
    (fetch-all-rows hstmt)))

(defun %sql-data-sources (henv &key (direction :first))
  (with-allocate-foreign-strings ((name-ptr (1+ $SQL_MAX_DSN_LENGTH))
                                  (description-ptr 1024))
   (with-foreign-objects ((name-length-ptr :short)
                          (description-length-ptr :short))
    (let ((res (with-error-handling
                   (:henv henv)
                   (SQLDataSources henv
                                   (ecase direction
                                     (:first $SQL_FETCH_FIRST)
                                     (:next $SQL_FETCH_NEXT))
                                   name-ptr
                                   (1+ $SQL_MAX_DSN_LENGTH)
                                   name-length-ptr
                                   description-ptr
                                   1024
                                   description-length-ptr))))
      (when (= res $SQL_NO_DATA_FOUND)
        (values
          (convert-from-foreign-string name-ptr)
          (convert-from-foreign-string description-ptr)))))))



(defun sql-to-c-type (sql-type)
  (ecase sql-type
    ;; Added -10 for MSSQL ntext type and -11 for nvarchar
    ((#.$SQL_CHAR #.$SQL_VARCHAR #.$SQL_LONGVARCHAR
      #.$SQL_NUMERIC #.$sql_decimal -8 -9 -10 -11) $SQL_C_CHAR)
    (#.$SQL_INTEGER $SQL_C_SLONG)
    (#.$SQL_BIGINT $SQL_C_SBIGINT)
    (#.$SQL_SMALLINT $SQL_C_SSHORT)
    (#.$SQL_DOUBLE $SQL_C_DOUBLE)
    (#.$SQL_FLOAT $SQL_C_DOUBLE)
    (#.$SQL_REAL $SQL_C_FLOAT)
    (#.$SQL_DATE $SQL_C_DATE)
    (#.$SQL_TIME $SQL_C_TIME)
    (#.$SQL_TIMESTAMP $SQL_C_TIMESTAMP)
    (#.$SQL_TYPE_DATE $SQL_C_TYPE_DATE)
    (#.$SQL_TYPE_TIME $SQL_C_TYPE_TIME)
    (#.$SQL_TYPE_TIMESTAMP $SQL_C_TYPE_TIMESTAMP)
    ((#.$SQL_BINARY #.$SQL_VARBINARY #.$SQL_LONGVARBINARY) $SQL_C_BINARY)
    (#.$SQL_TINYINT $SQL_C_STINYINT)
    (#.$SQL_BIT $SQL_C_BIT)))

(def-type byte-pointer-type (* :byte))
(def-type short-pointer-type (* :short))
(def-type int-pointer-type (* :int))
(def-type long-pointer-type (* #.$ODBC-LONG-TYPE))
(def-type big-pointer-type (* #.$ODBC-BIG-TYPE))
(def-type float-pointer-type (* :float))
(def-type double-pointer-type (* :double))
(def-type string-pointer-type (* :unsigned-char))

(defun get-cast-byte (ptr)
  (locally (declare (type byte-pointer-type ptr))
    (deref-pointer ptr :byte)))

(defun get-cast-short (ptr)
  (locally (declare (type short-pointer-type ptr))
    (deref-pointer ptr :short)))

(defun get-cast-int (ptr)
  (locally (declare (type int-pointer-type ptr))
    (deref-pointer ptr :int)))

(defun get-cast-long (ptr)
  (locally (declare (type long-pointer-type ptr))
    (deref-pointer ptr #.$ODBC-LONG-TYPE)))

(defun get-cast-big (ptr)
  (locally (declare (type big-pointer-type ptr))
    (deref-pointer ptr #.$ODBC-BIG-TYPE)))

(defun get-cast-single-float (ptr)
  (locally (declare (type float-pointer-type ptr))
    (deref-pointer ptr :float)))

(defun get-cast-double-float (ptr)
  (locally (declare (type double-pointer-type ptr))
    (deref-pointer ptr :double)))

(defun get-cast-foreign-string (ptr)
  (locally (declare (type string-pointer-type ptr))
    (convert-from-foreign-string ptr)))

(defun get-cast-binary (ptr len format)
  "FORMAT is one of :unsigned-byte-vector, :bit-vector (:string, :hex-string)"
  (with-cast-pointer (casted ptr :unsigned-byte)
    (ecase format
      (:unsigned-byte-vector
       (let ((vector (make-array len :element-type '(unsigned-byte 8))))
         (dotimes (i len)
           (setf (aref vector i)
                 (deref-array casted '(:array :unsigned-byte) i)))
         vector))
      (:bit-vector
       (let ((vector (make-array (ash len 3) :element-type 'bit)))
         (dotimes (i len)
           (let ((byte (deref-array casted '(:array :byte) i)))
             (dotimes (j 8)
               (setf (bit vector (+ (ash i 3) j))
                     (logand (ash byte (- j 7)) 1)))))
         vector)))))


(defun read-data (data-ptr c-type sql-type out-len-ptr result-type)
  ;;(declare (type long-ptr-type out-len-ptr))
  (let* (;;(out-len (get-cast-long out-len-ptr))
	 (out-len (uffi:deref-pointer out-len-ptr #.$ODBC-SQLLEN-TYPE))
         (value
          (cond ((= out-len $SQL_NULL_DATA) *null*)
                (t
                 (case sql-type
                   ;; SQL extended datatypes
                   (#.$SQL_TINYINT  (get-cast-byte data-ptr))
                   (#.$SQL_C_STINYINT (get-cast-byte data-ptr)) ;; ?
                   (#.$SQL_C_SSHORT (get-cast-short data-ptr)) ;; ?
                   (#.$SQL_SMALLINT (get-cast-short data-ptr)) ;; ??
                   (#.$SQL_INTEGER (get-cast-int data-ptr))
                   (#.$SQL_BIGINT (get-cast-big data-ptr))
                   ;; TODO: Change this to read in rationals instead of doubles
                   ((#.$SQL_DECIMAL #.$SQL_NUMERIC)
                     (let* ((*read-base* 10)
                            (*read-default-float-format* 'double-float)
                            (str (get-cast-foreign-string data-ptr)))
                       (read-from-string str)))
                   (#.$SQL_BIT (get-cast-byte data-ptr))
                   (t
                    (case c-type
                      ((#.$SQL_C_DATE #.$SQL_C_TYPE_DATE)
                       (funcall *time-format* (date-to-clsql-time data-ptr)))
                      ((#.$SQL_C_TIME #.$SQL_C_TYPE_TIME)
		       (funcall *time-format* (time-to-clsql-time data-ptr)))
                      ((#.$SQL_C_TIMESTAMP #.$SQL_C_TYPE_TIMESTAMP)
		       (funcall *time-format* (timestamp-to-clsql-time data-ptr)))
                      (#.$SQL_INTEGER
                       (get-cast-int data-ptr))
                      (#.$SQL_C_FLOAT
                       (get-cast-single-float data-ptr))
                      (#.$SQL_C_DOUBLE
                       (get-cast-double-float data-ptr))
                      (#.$SQL_C_SLONG
                       (get-cast-long data-ptr))
                      #+lispworks
                      (#.$SQL_C_BIT     ; encountered only in Access
                       (get-cast-byte data-ptr))
                      (#.$SQL_C_BINARY
                       (get-cast-binary data-ptr out-len *binary-format*))
                      ((#.$SQL_C_SSHORT #.$SQL_C_STINYINT) ; LMH short ints
                       (get-cast-short data-ptr)) ; LMH
                      (#.$SQL_C_SBIGINT (get-cast-big data-ptr))
                      #+ignore
                      (#.$SQL_C_CHAR
                       (code-char (get-cast-short data-ptr)))
                      (t
                       (get-cast-foreign-string data-ptr)))))))))

    ;; FIXME: this could be better optimized for types which use READ-FROM-STRING above

    (if (and (or (eq result-type t) (eq result-type :string))
             value
             (not (stringp value)))
        (write-to-string value)
      value)))

;; which value is appropriate?
(defparameter +max-precision+  4001)

(defvar *break-on-unknown-data-type* t)

;; C. Stacy's idea to factor this out
;; "Make it easy to add new datatypes by making new subroutine %ALLOCATE-BINDINGS,
;; so that I don't have to remember to make changes in more than one place.
;; Just keep it in synch with READ-DATA."
(defun %allocate-bindings (sql-type precision)
  (let* ((c-type (sql-to-c-type sql-type))
         (size (if (zerop precision)
                   +max-precision+ ;; if the precision cannot be determined
                 (min precision +max-precision+)))
         (long-p (= size +max-precision+))
         (data-ptr
          (case c-type ;; add more?
            (#.$SQL_C_SLONG (uffi:allocate-foreign-object #.$ODBC-LONG-TYPE))
            ((#.$SQL_C_DATE #.$SQL_C_TYPE_DATE) (allocate-foreign-object 'sql-c-date))
            ((#.$SQL_C_TIME #.$SQL_C_TYPE_TIME) (allocate-foreign-object 'sql-c-time))
            ((#.$SQL_C_TIMESTAMP #.$SQL_C_TYPE_TIMESTAMP) (allocate-foreign-object 'sql-c-timestamp))
            (#.$SQL_C_FLOAT (uffi:allocate-foreign-object :float))
            (#.$SQL_C_DOUBLE (uffi:allocate-foreign-object :double))
            (#.$SQL_C_BIT (uffi:allocate-foreign-object :byte))
            (#.$SQL_C_STINYINT (uffi:allocate-foreign-object :byte))
            (#.$SQL_C_SBIGINT (uffi:allocate-foreign-object #.$ODBC-BIG-TYPE))
            (#.$SQL_C_SSHORT (uffi:allocate-foreign-object :short))
            (#.$SQL_C_CHAR (uffi:allocate-foreign-string (1+ size)))
            (#.$SQL_C_BINARY (uffi:allocate-foreign-string (1+ (* 2 size))))
            (t
                ;; Maybe should signal a restartable condition for this?
                (when *break-on-unknown-data-type*
                  (break "SQL type is ~A, precision ~D, size ~D, C type is ~A"
                         sql-type precision size c-type))
                (uffi:allocate-foreign-object :byte (1+ size)))))
	 (out-len-ptr (uffi:allocate-foreign-object #.$ODBC-SQLLEN-TYPE)))
    (values c-type data-ptr out-len-ptr size long-p)))

(defun fetch-all-rows (hstmt &key free-option flatp)
  (let ((column-count (result-columns-count hstmt)))
    (unless (zerop column-count)
      (let ((names (make-array column-count))
            (sql-types (make-array column-count :element-type 'fixnum))
            (c-types (make-array column-count :element-type 'fixnum))
            (precisions (make-array column-count :element-type 'fixnum))
            (data-ptrs (make-array column-count :initial-element nil))
            (out-len-ptrs (make-array column-count :initial-element nil))
            (scales (make-array column-count :element-type 'fixnum))
            (nullables-p (make-array column-count :element-type 'fixnum)))
        (unwind-protect
          (values
           (progn
             (dotimes (col-nr column-count)
               ;; get column information
               (multiple-value-bind (name sql-type precision scale nullable-p)
                                    (%describe-column hstmt (1+ col-nr))
                 ;; allocate space to bind result rows to
                 (multiple-value-bind (c-type data-ptr out-len-ptr)
                     (%allocate-bindings sql-type precision)
                   (%bind-column hstmt col-nr c-type data-ptr (1+ precision) out-len-ptr)
                   (setf (svref names col-nr) name
                         (aref sql-types col-nr) sql-type
                         (aref c-types col-nr) (sql-to-c-type sql-type)
                         (aref precisions col-nr) (if (zerop precision) 0 precision)
                         (aref scales col-nr) scale
                         (aref nullables-p col-nr) nullable-p
                         (aref data-ptrs col-nr) data-ptr
                         (aref out-len-ptrs col-nr) out-len-ptr))))
             ;; the main loop
             (prog1
               (cond (flatp
                      (when (> column-count 1)
                        (error 'clsql:sql-database-error
                               :message "If more than one column is to be fetched, flatp has to be nil."))
                      (loop until (= (%sql-fetch hstmt) $SQL_NO_DATA_FOUND)
                            collect
                            (read-data (aref data-ptrs 0)
                                       (aref c-types 0)
                                       (aref sql-types 0)
                                       (aref out-len-ptrs 0)
                                       t)))
                     (t
                      (loop until (= (%sql-fetch hstmt) $SQL_NO_DATA_FOUND)
                            collect
                            (loop for col-nr from 0 to (1- column-count)
                                  collect
                                  (read-data (aref data-ptrs col-nr)
                                             (aref c-types col-nr)
                                             (aref sql-types col-nr)
                                             (aref out-len-ptrs col-nr)
                                             t)))))))
           names)
          ;; dispose of memory etc
          (when free-option (%free-statement hstmt free-option))
          (dotimes (col-nr column-count)
            (let ((data-ptr (aref data-ptrs col-nr))
                  (out-len-ptr (aref out-len-ptrs col-nr)))
              (when data-ptr (free-foreign-object data-ptr)) ; we *did* allocate them
              (when out-len-ptr (free-foreign-object out-len-ptr)))))))))

;; to do: factor out common parts, put the sceleton (the obligatory macro part)
;; of %do-fetch into sql package (has been done)

(defun %sql-prepare (hstmt sql)
  (with-cstring (sql-ptr sql)
    (with-error-handling (:hstmt hstmt)
      (SQLPrepare hstmt sql-ptr $SQL_NTS))))

;; depending on option, we return a long int or a string; string not implemented
(defun get-connection-option (hdbc option)
  (with-foreign-object (param-ptr #.$ODBC-LONG-TYPE)
    (with-error-handling (:hdbc hdbc)
                         (SQLGetConnectOption hdbc option param-ptr)
      (deref-pointer param-ptr #.$ODBC-LONG-TYPE))))

(defun set-connection-option (hdbc option param)
  (with-error-handling (:hdbc hdbc)
    (SQLSetConnectOption hdbc option param)))

(defun disable-autocommit (hdbc)
  (set-connection-option hdbc $SQL_AUTOCOMMIT $SQL_AUTOCOMMIT_OFF))

(defun enable-autocommit (hdbc)
  (set-connection-option hdbc $SQL_AUTOCOMMIT $SQL_AUTOCOMMIT_ON))

(defun %sql-set-pos (hstmt row option lock)
  (with-error-handling
    (:hstmt hstmt)
    (SQLSetPos hstmt row option lock)))

(defun %sql-extended-fetch (hstmt fetch-type row)
  (with-foreign-objects ((row-count-ptr #.$ODBC-ULONG-TYPE)
                         (row-status-ptr :short))
    (with-error-handling (:hstmt hstmt)
      (SQLExtendedFetch hstmt fetch-type row row-count-ptr
                        row-status-ptr)
      (values (deref-pointer row-count-ptr #.$ODBC-ULONG-TYPE)
              (deref-pointer row-status-ptr :short)))))

; column-nr is zero-based
(defun %sql-get-data (hstmt column-nr c-type data-ptr precision out-len-ptr)
  (with-error-handling
    (:hstmt hstmt :print-info nil)
    (SQLGetData hstmt (if (eq column-nr :bookmark) 0 (1+ column-nr))
                c-type data-ptr precision out-len-ptr)))

(defun %sql-param-data (hstmt param-ptr)
  (with-error-handling (:hstmt hstmt :print-info t) ;; nil
      (SQLParamData hstmt param-ptr)))

(defun %sql-put-data (hstmt data-ptr size)
  (with-error-handling
    (:hstmt hstmt :print-info t) ;; nil
    (SQLPutData hstmt data-ptr size)))

(defconstant $sql-data-truncated (intern "01004" :keyword))


(defun read-data-in-chunks (hstmt column-nr data-ptr c-type sql-type
                            out-len-ptr result-type)
  (declare ;;(type long-ptr-type out-len-ptr)
           (ignore result-type))

  (let* ((res (%sql-get-data hstmt column-nr c-type data-ptr
                             +max-precision+ out-len-ptr))
         ;; (out-len (get-cast-long out-len-ptr))
	 (out-len (uffi:deref-pointer out-len-ptr #.$ODBC-SQLLEN-TYPE))
         (result (if (equal out-len #.$SQL_NULL_DATA)
                     (return-from read-data-in-chunks *null*)
                     
                     ;;this isn't the most efficient way of doing it:
                     ;;the foreign string gets copied to lisp, then
                     ;;that is copied into the final string. However,
                     ;;the previous impl that tried to copy one
                     ;;character over at a time failed miserably on
                     ;;multibyte characters.
                     ;;
                     ;;In the face of multibyte characters, the out-len
                     ;;tells us the length in bytes but that doesn't
                     ;;particularly help us here in allocating a lisp
                     ;;array. So our best strategy is to just let the
                     ;;foreign library that's already dealing with
                     ;;encodings do its thing.
                   
                     (with-output-to-string (str)
                       (loop do (if (= c-type #.$SQL_CHAR)
                                    (write-sequence (get-cast-foreign-string data-ptr) str)
                                    (error 'clsql:sql-database-error
                                           :message "wrong type. preliminary."))
                             while (and (= res $SQL_SUCCESS_WITH_INFO)
                                        (equal (sql-state +null-handle-ptr+ +null-handle-ptr+ hstmt)
                                               "01004"))
                             do (setf res (%sql-get-data hstmt column-nr c-type data-ptr
                                                         +max-precision+ out-len-ptr)))))))

    ;; reset the out length for the next row
    (setf (deref-pointer out-len-ptr #.$ODBC-SQLLEN-TYPE) #.$SQL_NO_TOTAL)
    (if (= sql-type $SQL_DECIMAL)
        (let ((*read-base* 10))
          (read-from-string result))
        result)))


(def-type c-timestamp-ptr-type (* (:struct sql-c-timestamp)))
(def-type c-time-ptr-type (* (:struct sql-c-time)))
(def-type c-date-ptr-type (* (:struct sql-c-date)))

(defun timestamp-to-clsql-time (ptr)
  (declare (type c-timestamp-ptr-type ptr))
  (clsql-sys:make-time
   :second (get-slot-value ptr 'sql-c-timestamp 'second)
   :minute (get-slot-value ptr 'sql-c-timestamp 'minute)
   :hour (get-slot-value ptr 'sql-c-timestamp 'hour)
   :day (get-slot-value ptr 'sql-c-timestamp 'day)
   :month (get-slot-value ptr 'sql-c-timestamp 'month)
   :year (get-slot-value ptr 'sql-c-timestamp 'year)
   :usec (let ((frac (get-slot-value ptr 'sql-c-timestamp 'fraction)))
	   (if frac (/ frac 1000) 0))))

(defun universal-time-to-timestamp (time &optional (fraction 0))
  "TODO: Dead function?"
  (multiple-value-bind (sec min hour day month year)
      (decode-universal-time time)
    (let ((ptr (allocate-foreign-object 'sql-c-timestamp)))
      (setf (get-slot-value ptr 'sql-c-timestamp 'second) sec
            (get-slot-value ptr 'sql-c-timestamp 'minute) min
            (get-slot-value ptr 'sql-c-timestamp 'hour) hour
            (get-slot-value ptr 'sql-c-timestamp 'day) day
            (get-slot-value ptr 'sql-c-timestamp 'month) month
            (get-slot-value ptr 'sql-c-timestamp 'year) year
            (get-slot-value ptr 'sql-c-timestamp 'fraction) fraction)
      ptr)))

(defun %put-timestamp (ptr time &optional (fraction 0))
  "TODO: Dead function?"
  (declare (type c-timestamp-ptr-type ptr))
  (multiple-value-bind (sec min hour day month year)
      (decode-universal-time time)
    (setf (get-slot-value ptr 'sql-c-timestamp 'second) sec
          (get-slot-value ptr 'sql-c-timestamp 'minute) min
          (get-slot-value ptr 'sql-c-timestamp 'hour) hour
          (get-slot-value ptr 'sql-c-timestamp 'day) day
          (get-slot-value ptr 'sql-c-timestamp 'month) month
          (get-slot-value ptr 'sql-c-timestamp 'year) year
          (get-slot-value ptr 'sql-c-timestamp 'fraction) fraction)
      ptr))

(defun date-to-clsql-time (ptr)
  (declare (type c-date-ptr-type ptr))
  (clsql-sys:make-time
   :second 0 :minute 0 :hour 0
   :day (get-slot-value ptr 'sql-c-timestamp 'day)
   :month (get-slot-value ptr 'sql-c-timestamp 'month)
   :year (get-slot-value ptr 'sql-c-timestamp 'year)))

(defun time-to-clsql-time (ptr)
  (declare (type c-time-ptr-type ptr))
  (clsql-sys:make-time
   :second (get-slot-value ptr 'sql-c-timestamp 'second)
   :minute (get-slot-value ptr 'sql-c-timestamp 'minute)
   :hour (get-slot-value ptr 'sql-c-timestamp 'hour)))


;;; Added by KMR

(defun %set-attr-odbc-version (henv version)
  (with-error-handling (:henv henv)
      ;;note that we are passing version as an integer that happens to be
      ;;stuffed into a pointer.
      ;;http://msdn.microsoft.com/en-us/library/ms709285%28v=VS.85%29.aspx
      (SQLSetEnvAttr henv $SQL_ATTR_ODBC_VERSION
                     (make-pointer version :void) 0)))

(defun %list-tables (hstmt)
  (with-error-handling (:hstmt hstmt)
    (SQLTables hstmt +null-ptr+ 0 +null-ptr+ 0 +null-ptr+ 0 +null-ptr+ 0)))

(defun %table-statistics (table hstmt &key unique (ensure t)
                           &aux (table (princ-to-string
                                        (clsql-sys::unescaped-database-identifier table))))
  (with-cstrings ((table-cs table))
   (with-error-handling (:hstmt hstmt)
       (SQLStatistics
        hstmt
        +null-ptr+ 0
        +null-ptr+ 0
        table-cs $SQL_NTS
        (if unique $SQL_INDEX_UNIQUE $SQL_INDEX_ALL)
        (if ensure $SQL_ENSURE $SQL_QUICK)))))

(defun %list-data-sources (henv)
  (let ((results nil))
    (with-foreign-strings ((dsn-ptr (1+ $SQL_MAX_DSN_LENGTH))
                           (desc-ptr 256))
      (with-foreign-objects ((dsn-len :short)
                             (desc-len :short))
       (let ((res (with-error-handling (:henv henv)
                      (SQLDataSources henv $SQL_FETCH_FIRST dsn-ptr
                                      (1+ $SQL_MAX_DSN_LENGTH)
                                      dsn-len desc-ptr 256 desc-len))))
         (when (or (eql res $SQL_SUCCESS)
                   (eql res $SQL_SUCCESS_WITH_INFO))
           (push (convert-from-foreign-string dsn-ptr) results))

         (do ((res (with-error-handling (:henv henv)
                       (SQLDataSources henv $SQL_FETCH_NEXT dsn-ptr
                                       (1+ $SQL_MAX_DSN_LENGTH)
                                       dsn-len desc-ptr 256 desc-len))
                   (with-error-handling (:henv henv)
                       (SQLDataSources henv $SQL_FETCH_NEXT dsn-ptr
                                       (1+ $SQL_MAX_DSN_LENGTH)
                                       dsn-len desc-ptr 256 desc-len))))
             ((not (or (eql res $SQL_SUCCESS)
                       (eql res $SQL_SUCCESS_WITH_INFO))))
           (push (convert-from-foreign-string dsn-ptr) results)))))
    (nreverse results)))
