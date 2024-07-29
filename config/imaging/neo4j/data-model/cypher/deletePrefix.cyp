MATCH(o:`ApplicationName`:ObjectType)
SET o.objectType = REPLACE(o.objectType, "_", " ");

MATCH(o:`ApplicationName`:ObjectType)
SET o.objectType = REPLACE(o.objectType,"ApplicationName ","");