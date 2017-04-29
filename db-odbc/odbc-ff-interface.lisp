;;;; -*- Mode: LISP; Syntax: ANSI-Common-Lisp; Package: odbc -*-
;;;; *************************************************************************
;;;; FILE IDENTIFICATION
;;;;
;;;; Name:     odbc-ff-interface.lisp
;;;; Purpose:  Function definitions for UFFI interface to ODBC
;;;; Author:   Kevin M. Rosenberg
;;;;
;;;; This file, part of CLSQL, is Copyright (c) 2004 by Kevin M. Rosenberg
;;;; and Copyright (C) Paul Meurer 1999 - 2001. All rights reserved.
;;;;
;;;; CLSQL users are granted the rights to distribute and use this software
;;;; as governed by the terms of the Lisp Lesser GNU Public License
;;;; (http://opensource.franz.com/preamble.html), also known as the LLGPL.
;;;; *************************************************************************

(in-package #:odbc)

(def-foreign-type sql-handle :pointer-void)
(def-foreign-type sql-handle-ptr (* sql-handle))
(def-foreign-type string-ptr (* :unsigned-char))
(def-type long-ptr-type (* #.$ODBC-LONG-TYPE))

;; ODBC3
(def-function "SQLAllocHandle"
    ((handle-type :short)
     (input-handle sql-handle)
     (*phenv sql-handle-ptr))
  :module "odbc"
  :returning :short)

;; ODBC3 version of SQLFreeStmt, SQLFreeConnect, and SSQLFreeStmt
(def-function "SQLFreeHandle"
    ((handle-type :short)        ; HandleType
     (input-handle sql-handle))  ; Handle
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API


;; deprecated
(def-function "SQLAllocEnv"
    ((*phenv sql-handle-ptr)    ; HENV   FAR *phenv
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

;; deprecated
(def-function "SQLAllocConnect"
    ((henv sql-handle)          ; HENV        henv
     (*phdbc sql-handle-ptr)    ; HDBC   FAR *phdbc
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

(def-function "SQLConnect"
    ((hdbc sql-handle)          ; HDBC        hdbc
     (*szDSN :cstring)        ; UCHAR  FAR *szDSN
     (cbDSN :short)             ; SWORD       cbDSN
     (*szUID :cstring)        ; UCHAR  FAR *szUID
     (cbUID :short)             ; SWORD       cbUID
     (*szAuthStr :cstring)    ; UCHAR  FAR *szAuthStr
     (cbAuthStr :short)         ; SWORD       cbAuthStr
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

(def-function "SQLDriverConnect"
    ((hdbc sql-handle)          ; HDBC        hdbc
     (hwnd sql-handle)          ; SQLHWND     hwnd
     (*szConnStrIn :cstring)    ; UCHAR  FAR *szConnStrIn
     (cbConnStrIn :short)       ; SWORD       cbConnStrIn
     (*szConnStrOut string-ptr) ; UCHAR  FAR *szConnStrOut
     (cbConnStrOutMax :short)   ; SWORD       cbConnStrOutMax
     (*pcbConnStrOut :pointer-void)      ; SWORD  FAR *pcbConnStrOut
     (fDriverCompletion :short) ; UWORD       fDriverCompletion
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

(def-function "SQLDisconnect"
    ((hdbc sql-handle))         ; HDBC        hdbc
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API


;;deprecated
(def-function "SQLFreeConnect"
    ((hdbc sql-handle))         ; HDBC        hdbc
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

;; deprecated
(def-function "SQLAllocStmt"
    ((hdbc sql-handle)          ; HDBC        hdbc
     (*phstmt sql-handle-ptr)   ; HSTMT  FAR *phstmt
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

(def-function "SQLGetInfo"
    ((hdbc sql-handle)          ; HDBC        hdbc
     (fInfoType :short)         ; UWORD       fInfoType
     (rgbInfoValue :pointer-void)        ; PTR         rgbInfoValue
     (cbInfoValueMax :short)    ; SWORD       cbInfoValueMax
     (*pcbInfoValue :pointer-void)       ; SWORD  FAR *pcbInfoValue
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

(def-function "SQLPrepare"
    ((hstmt sql-handle)         ; HSTMT       hstmt
     (*szSqlStr :cstring)     ; UCHAR  FAR *szSqlStr
     (cbSqlStr :int)           ; SDWORD      cbSqlStr
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

(def-function "SQLExecute"
    ((hstmt sql-handle)         ; HSTMT       hstmt
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

(def-function "SQLExecDirect"
    ((hstmt sql-handle)         ; HSTMT       hstmt
     (*szSqlStr :cstring)     ; UCHAR  FAR *szSqlStr
     (cbSqlStr :int)           ; SDWORD      cbSqlStr
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

(def-function "SQLFreeStmt"
    ((hstmt sql-handle)         ; HSTMT       hstmt
     (fOption :short))          ; UWORD       fOption
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

  (def-function "SQLCancel"
      ((hstmt sql-handle)         ; HSTMT       hstmt
       )
    :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

(def-function "SQLError"
    ((henv sql-handle)          ; HENV        henv
     (hdbc sql-handle)          ; HDBC        hdbc
     (hstmt sql-handle)         ; HSTMT       hstmt
     (*szSqlState string-ptr)   ; UCHAR  FAR *szSqlState
     (*pfNativeError (* :int))      ; SDWORD FAR *pfNativeError
     (*szErrorMsg string-ptr)   ; UCHAR  FAR *szErrorMsg
     (cbErrorMsgMax :short)     ; SWORD       cbErrorMsgMax
     (*pcbErrorMsg (* :short))        ; SWORD  FAR *pcbErrorMsg
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

(def-function "SQLNumResultCols"
    ((hstmt sql-handle)         ; HSTMT       hstmt
     (*pccol (* :short))              ; SWORD  FAR *pccol
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

#-:x86-64
(def-function "SQLRowCount"
    ((hstmt sql-handle)         ; HSTMT       hstmt
     (*pcrow (* :int))              ; SDWORD FAR *pcrow
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

#-:x86-64
(def-function "SQLDescribeCol"
    ((hstmt sql-handle)         ; HSTMT       hstmt
     (icol :short)              ; UWORD       icol
     (*szColName string-ptr)    ; UCHAR  FAR *szColName
     (cbColNameMax :short)      ; SWORD       cbColNameMax
     (*pcbColName (* :short))         ; SWORD  FAR *pcbColName
     (*pfSqlType (* :short))          ; SWORD  FAR *pfSqlType
     (*pcbColDef (* #.$ODBC-ULONG-TYPE))          ; UDWORD FAR *pcbColDef
     (*pibScale (* :short))           ; SWORD  FAR *pibScale
     (*pfNullable (* :short))         ; SWORD  FAR *pfNullable
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

#-:x86-64
(def-function "SQLColAttributes"
    ((hstmt sql-handle)         ; HSTMT       hstmt
     (icol :short)              ; UWORD       icol
     (fDescType :short)         ; UWORD       fDescType
     (rgbDesc string-ptr)             ; PTR         rgbDesc
     (cbDescMax :short)         ; SWORD       cbDescMax
     (*pcbDesc (* :short))            ; SWORD  FAR *pcbDesc
     (*pfDesc (* :int))             ; SDWORD FAR *pfDesc
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

(def-function "SQLColumns"
    ((hstmt sql-handle)             ; HSTMT       hstmt
     (*szTableQualifier :cstring) ; UCHAR  FAR *szTableQualifier
     (cbTableQualifier :short)      ; SWORD       cbTableQualifier
     (*szTableOwner :cstring)     ; UCHAR  FAR *szTableOwner
     (cbTableOwner :short)          ; SWORD       cbTableOwner
     (*szTableName :cstring)      ; UCHAR  FAR *szTableName
     (cbTableName :short)           ; SWORD       cbTableName
     (*szColumnName :cstring)     ; UCHAR  FAR *szColumnName
     (cbColumnName :short)          ; SWORD       cbColumnName
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

#-:x86-64
(def-function "SQLBindCol"
    ((hstmt sql-handle)         ; HSTMT       hstmt
     (icol :short)              ; UWORD       icol
     (fCType :short)            ; SWORD       fCType
     (rgbValue :pointer-void)            ; PTR         rgbValue
     (cbValueMax :int)         ; SDWORD      cbValueMax
     (*pcbValue (* :int))           ; SDWORD FAR *pcbValue
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

(def-function "SQLFetch"
    ((hstmt sql-handle)         ; HSTMT       hstmt
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

(def-function "SQLTransact"
    ((henv sql-handle)          ; HENV        henv
     (hdbc sql-handle)          ; HDBC        hdbc
     (fType :short)             ; UWORD       fType ($SQL_COMMIT or $SQL_ROLLBACK)
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

;; ODBC 2.0
#-:x86-64
(def-function "SQLDescribeParam"
    ((hstmt sql-handle)         ; HSTMT       hstmt
     (ipar :short)              ; UWORD       ipar
     (*pfSqlType (* :short))          ; SWORD  FAR *pfSqlType
     (*pcbColDef (* :unsigned-int))          ; UDWORD FAR *pcbColDef
     (*pibScale (* :short))           ; SWORD  FAR *pibScale
     (*pfNullable (* :short))         ; SWORD  FAR *pfNullable
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

;; ODBC 2.0
#-:x86-64
(def-function "SQLBindParameter"
    ((hstmt sql-handle)         ; HSTMT       hstmt
     (ipar :short)              ; UWORD       ipar
     (fParamType :short)        ; SWORD       fParamType
     (fCType :short)            ; SWORD       fCType
     (fSqlType :short)          ; SWORD       fSqlType
     (cbColDef :int)           ; UDWORD      cbColDef
     (ibScale :short)           ; SWORD       ibScale
     (rgbValue :pointer-void)            ; PTR         rgbValue
     (cbValueMax :int)         ; SDWORD      cbValueMax
     (*pcbValue :pointer-void)           ; SDWORD FAR *pcbValue
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

;; level 1
#-:x86-64
(def-function "SQLGetData"
    ((hstmt sql-handle)         ; HSTMT       hstmt
     (icol :short)              ; UWORD       icol
     (fCType :short)            ; SWORD       fCType
     (rgbValue :pointer-void)            ; PTR         rgbValue
     (cbValueMax :int)         ; SDWORD      cbValueMax
     (*pcbValue :pointer-void)           ; SDWORD FAR *pcbValue
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

(def-function "SQLParamData"
    ((hstmt sql-handle)         ; HSTMT       hstmt
     (*prgbValue :pointer-void)          ; PTR    FAR *prgbValue
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

#-:x86-64
(def-function "SQLPutData"
    ((hstmt sql-handle)         ; HSTMT       hstmt
     (rgbValue :pointer-void)            ; PTR         rgbValue
     (cbValue :int)            ; SDWORD      cbValue
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

(def-function "SQLGetConnectOption"
    ((hdbc sql-handle)          ; HDBC        hdbc
     (fOption :short)           ; UWORD       fOption
     (pvParam :pointer-void)             ; PTR         pvParam
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

#-:x86-64
(def-function "SQLSetConnectOption"
    ((hdbc sql-handle)          ; HDBC        hdbc
     (fOption :short)           ; UWORD       fOption
     (vParam :int)             ; UDWORD      vParam
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

#-:x86-64
(def-function "SQLSetPos"
    ((hstmt sql-handle)         ; HSTMT       hstmt
     (irow :short)              ; UWORD       irow
     (fOption :short)           ; UWORD       fOption
     (fLock :short)             ; UWORD       fLock
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

                                       ; level 2
#-:x86-64
(def-function "SQLExtendedFetch"
    ((hstmt sql-handle)         ; HSTMT       hstmt
     (fFetchType :short)        ; UWORD       fFetchType
     (irow :int)               ; SDWORD      irow
     (*pcrow :pointer-void)              ; UDWORD FAR *pcrow
     (*rgfRowStatus :pointer-void)       ; UWORD  FAR *rgfRowStatus
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

(def-function "SQLDataSources"
    ((henv sql-handle)          ; HENV        henv
     (fDirection :short)
     (*szDSN string-ptr)        ; UCHAR  FAR *szDSN
     (cbDSNMax :short)          ; SWORD       cbDSNMax
     (*pcbDSN (* :short))             ; SWORD      *pcbDSN
     (*szDescription string-ptr) ; UCHAR     *szDescription
     (cbDescriptionMax :short)  ; SWORD       cbDescriptionMax
     (*pcbDescription (* :short))     ; SWORD      *pcbDescription
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API

(def-function "SQLFreeEnv"
    ((henv sql-handle)          ; HSTMT       hstmt
     )
  :module "odbc"
  :returning :short)              ; RETCODE_SQL_API


;;; foreign type definitions

;;(defmacro %sql-len-data-at-exec (length)
;;  `(- $SQL_LEN_DATA_AT_EXEC_OFFSET ,length))


(def-struct sql-c-time
    (hour   :short)
  (minute :short)
  (second :short))

(def-struct sql-c-date
    (year  :short)
  (month :short)
  (day   :short))

(def-struct sql-c-timestamp
    (year     :short)
  (month    :short)
  (day      :short)
  (hour     :short)
  (minute   :short)
  (second   :short)
  (fraction :int))

;;; Added by KMR

(def-function "SQLSetEnvAttr"
    ((henv sql-handle)          ; HENV        henv
     (attr :int)
     (*value :pointer-void)
     (szLength :int))
  :module "odbc"
  :returning :short)

(def-function "SQLGetEnvAttr"
    ((henv sql-handle)          ; HENV        henv
     (attr :int)
     (*value :pointer-void)
     (szLength :int)
     (string-length-ptr (* :int)))
  :module "odbc"
  :returning :short)

(def-function "SQLTables"
    ((hstmt :pointer-void)
     (catalog-name :pointer-void)
     (catalog-name-length :short)
     (schema-name :pointer-void)
     (schema-name-length :short)
     (table-name :pointer-void)
     (table-name-length :short)
     (table-type-name :pointer-void)
     (table-type-name-length :short))
  :module "odbc"
  :returning :short)


(def-function "SQLStatistics"
    ((hstmt :pointer-void)
     (catalog-name :pointer-void)
     (catalog-name-length :short)
     (schema-name :pointer-void)
     (schema-name-length :short)
     (table-name :cstring)
     (table-name-length :short)
     (unique :short)
     (reserved :short))
  :module "odbc"
  :returning :short)


;;; 2017-04-28
;;; revision accoring to microsoft documentation regarding 64-bit api
;;; https://docs.microsoft.com/en-us/sql/odbc/reference/odbc-64-bit-information

#+:x86-64
(progn
(def-function "SQLBindCol"
    ((StatementHandle sql-handle)
     (ColumnNumber :unsigned-short)
     (TargetType :short)
     (TargetValuePtr :pointer-void)
     (BufferLength #.$ODBC-SQLLEN-TYPE)
     (*StrLen_or_Ind (* #.$ODBC-SQLLEN-TYPE)))
  :module "odbc"
  :returning :short)


(def-function "SQLBindParam"
    ((StatementHandle sql-handle)
     (ParameterNumber :unsigned-short)
     (ValueType :short)
     (ParameterType :short)
     (ColumnSize #.$ODBC-SQLULEN-TYPE)
     (DecimalDigits :short)
     (ParameterValuePtr :pointer-void)
     (*StrLen_or_Ind (* #.$ODBC-SQLLEN-TYPE)))
  :module "odbc"
  :returning :short)


(def-function "SQLBindParameter"
    ((StatementHandle sql-handle)
     (ParameterNumber :unsigned-short)
     (InputOutputType :short)
     (ValueType :short)
     (ParameterType :short)
     (ColumnSize #.$ODBC-SQLULEN-TYPE)
     (DecimalDigits :short)
     (ParameterValuePtr :pointer-void)
     (BufferLength #.$ODBC-SQLLEN-TYPE)
     (*StrLen_or_IndPtr (* #.$ODBC-SQLLEN-TYPE)))
  :module "odbc"
  :returning :short)


(def-function "SQLColAttribute"
    ((StatementHandle sql-handle)
     (ColumnNumber :unsigned-short)
     (FieldIdentifier :unsigned-short)
     (CharacterAttributePtr :pointer-void)
     (BufferLength :short)
     (*StringLengthPtr (* :short))
     (*NumericAttributePtr (* #.$ODBC-SQLLEN-TYPE)))
  :module "odbc"
  :returning :short)


(def-function "SQLColAttributes"
    ((hstmt sql-handle)
     (icol :unsigned-short)
     (fDescType :unsigned-short)
     (rgbDesc :pointer-void)
     (cbDescMax :short)
     (*pcbDesc (* :short))
     (*pfDesc (* #.$ODBC-SQLLEN-TYPE)))
  :module "odbc"
  :returning :short)


(def-function "SQLDescribeCol"
    ((StatementHandle sql-handle)
     (ColumnNumber :unsigned-short)
     (*ColumnName string-ptr)
     (BufferLength :short)
     (*NameLengthPtr (* :short))
     (*DataTypePtr (* :short))
     (*ColumnSizePtr (* #.$ODBC-SQLULEN-TYPE))
     (*DecimalDigitsPtr (* :short))
     (*NullablePtr (* :short)))
  :module "odbc"
  :returning :short)


(def-function "SQLDescribeParam"
    ((StatementHandle sql-handle)
     (ParameterNumber :unsigned-short)
     (*DataTypePtr (* :short))
     (*ParameterSizePtr (* #.$ODBC-SQLULEN-TYPE))
     (*DecimalDigitsPtr (* :short))
     (*NullablePtr (* :short)))
  :module "odbc"
  :returning :short)


(def-function "SQLExtendedFetch"
    ((StatementHandle sql-handle)
     (FetchOrientation :unsigned-short)
     (FetchOffset #.$ODBC-SQLLEN-TYPE)
     (*RowCountPtr (* #.$ODBC-SQLULEN-TYPE))
     (*RowStatusArray (* :unsigned-short)))
  :module "odbc"
  :returning :short)


(def-function "SQLFetchScroll"
    ((StatementHandle sql-handle)
     (FetchOrientation :short)
     (FetchOffset #.$ODBC-SQLLEN-TYPE))
  :module "odbc"
  :returning :short)


(def-function "SQLGetData"
    ((StatementHandle sql-handle)
     (ColumnNumber :unsigned-short)
     (TargetType :short)
     (TargetValuePtr :pointer-void)
     (BufferLength #.$ODBC-SQLLEN-TYPE)
     (*StrLen_or_Ind (* #.$ODBC-SQLLEN-TYPE)))
  :module "odbc"
  :returning :short)


(def-function "SQLGetDescRec"
    ((DescriptorHandle sql-handle)
     (RecNumber :short)
     (*Name string-ptr)
     (BufferLength :short)
     (*StringLengthPtr (* :short))
     (*TypePtr (* :short))
     (*SubTypePtr (* :short))
     (*LengthPtr (* #.$ODBC-SQLLEN-TYPE))
     (*PrecisionPtr (* :short))
     (*ScalePtr (* :short))
     (*NullablePtr (* :short)))
  :module "odbc"
  :returning :short)


(def-function "SQLParamOptions"
    ((hstmt sql-handle)
     (crow #.$ODBC-SQLULEN-TYPE)
     (*pirow (* #.$ODBC-SQLULEN-TYPE)))
  :module "odbc"
  :returning :short)


(def-function "SQLPutData"
    ((StatementHandle sql-handle)
     (DataPtr :pointer-void)
     (StrLen_or_Ind #.$ODBC-SQLLEN-TYPE))
  :module "odbc"
  :returning :short)


(def-function "SQLRowCount"
    ((StatementHandle sql-handle)
     (*RowCountPtr (* #.$ODBC-SQLLEN-TYPE)))
  :module "odbc"
  :returning :short)


(def-function "SQLSetConnectOption"
    ((ConnectHandle sql-handle)
     (Option :unsigned-short)
     (Value #.$ODBC-SQLULEN-TYPE))
  :module "odbc"
  :returning :short)


(def-function "SQLSetPos"
    ((StatementHandle sql-handle)
     (RowNumber :short)
     (Operation :unsigned-short)
     (LockType :unsigned-short))
  :module "odbc"
  :returning :short)


(def-function "SQLSetParam"
    ((StatementHandle sql-handle)
     (ParameterNumber :unsigned-short)
     (ValueType :short)
     (ParameterType :short)
     (LengthPrecision #.$ODBC-SQLULEN-TYPE)
     (ParameterScale :short)
     (ParameterValue :pointer-void)
     (*StrLen_or_Ind (* #.$ODBC-SQLLEN-TYPE)))
  :module "odbc"
  :returning :short)


(def-function "SQLSetDescRec"
    ((DescriptorHandle sql-handle)
     (RecNumber :short)
     (Type :short)
     (SubType :short)
     (Length #.$ODBC-SQLLEN-TYPE)
     (Precision :short)
     (Scale :short)
     (DataPtr :pointer-void)
     (*StringLengthPtr (* #.$ODBC-SQLLEN-TYPE))
     (*IndicatorPtr (* #.$ODBC-SQLLEN-TYPE)))
  :module "odbc"
  :returning :short)


(def-function "SQLSetScrollOptions"
    ((hstmt sql-handle)
     (fConcurrency :unsigned-short)
     (crowKeyset #.$ODBC-SQLLEN-TYPE)
     (crowRowset :unsigned-short))
  :module "odbc"
  :returning :short)
) ;; x86-64

