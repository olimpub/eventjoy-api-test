INSERT INTO [PTA].[tblChampionships]
    ([CName], [CDescription], [FromDate], [ToDate], [MultiLocatonFlg], [LocationID], [createdAt], [updatedAt])
VALUES
    -- 1. Több helyszínes, hosszabb bajnokság
    (N'Országos Bajnokság 2026', N'A 2026-os év országos, több állomásos bajnoksága.', '2026-09-01', '2026-12-15', 1, NULL, SYSDATETIMEOFFSET(), SYSDATETIMEOFFSET()),

    -- 2. Egy konkrét helyszínes bajnokság (pl. LocationID = 1)
    (N'Téli Kupa 2026', N'Hagyományos téli évzáró kupa.', '2026-12-20', '2026-12-22', 0, 1, SYSDATETIMEOFFSET(), SYSDATETIMEOFFSET()),

    -- 3. Jövő évi rövidebb torna
    (N'Tavaszi Meghívásos Torna 2027', N'Tavaszi szezonnyitó felkészülési torna.', '2027-03-10', '2027-03-12', 0, 2, SYSDATETIMEOFFSET(), SYSDATETIMEOFFSET());
GO
