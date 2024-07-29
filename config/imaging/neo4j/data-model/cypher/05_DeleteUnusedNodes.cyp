MATCH(t:Technology:`ApplicationName`:level5)
WHERE NOT EXISTS ((t)-->())
DETACH DELETE t;

MATCH(t:Technology:`ApplicationName`:level4)
WHERE not exists ((t)-->())
DETACH DELETE t;

MATCH(t:Technology:`ApplicationName`:level3)
WHERE not exists ((t)-->())
DETACH DELETE t;

MATCH(t:Technology:`ApplicationName`:level2)
WHERE not exists ((t)-->())
DETACH DELETE t;

MATCH(t:Technology:`ApplicationName`:level1)
WHERE not exists ((t)-->())
DETACH DELETE t;