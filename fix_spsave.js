const fs = require('fs');
let content = fs.readFileSync('SQL\\Procedures\\EJ.spSaveEvent.sql', 'utf8');

// Replace the @IsOP = 1 blocks for Roles, Tickets, and RoleTickets to just use the standard parsing (which was in the ELSE block)

// 1. Roles
let rolesRegex = /IF @IsOP = 1\s+BEGIN\s+-- Olimpub: Alapértelmezett Role-ok.*?END\s+ELSE\s+BEGIN\s+(INSERT INTO #IncomingRoles.*?FROM OPENJSON.*?WITH.*?;\s*)END/s;
content = content.replace(rolesRegex, "$1");

// 2. Tickets
let ticketsRegex = /IF @IsOP = 1\s+BEGIN\s+-- Olimpub: Automatikus Játékos jegy.*?END\s+ELSE\s+BEGIN\s+(INSERT INTO #IncomingTickets.*?FROM OPENJSON.*?WITH.*?;\s*)END/s;
content = content.replace(ticketsRegex, "$1");

// 3. RoleTickets
let roleTicketsRegex = /IF @IsOP = 1\s+BEGIN\s+-- Olimpub: Csak a Játékos.*?END\s+ELSE\s+BEGIN\s+(INSERT INTO \[EJ\]\.\[tblEventRoleTicket\].*?FROM OPENJSON.*?JOIN #IncomingTickets.*?;\s*)END/s;
content = content.replace(roleTicketsRegex, "$1");

fs.writeFileSync('SQL\\Procedures\\EJ.spSaveEvent.sql', content, 'utf8');
