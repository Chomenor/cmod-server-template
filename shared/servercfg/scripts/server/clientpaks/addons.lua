-- server/clientpaks/addons.lua

--[[===========================================================================================
Handle adding known client-side pk3s to the pure and download lists.
===========================================================================================--]]

local addons = core.init_module()

local utils = require("scripts/core/utils")
local svutils = require("scripts/server/svutils")

---------------------------------------------------------------------------------------
function addons.add_cmod_paks(ref_set)
  ref_set:add_pure_reference("baseEF/pakcmod-release-2023-09-18", -992215600)
  ref_set:add_download_reference("baseEF/pakcmod-release-2023-09-18", -992215600)
  ref_set:add_download_reference("baseEF/pakcmod-stock-2023-02-07", -447811514)
end

---------------------------------------------------------------------------------------
function addons.add_crosshairs(ref_set)
  ref_set:add_pure_reference("baseEF/pakhairs14", 1561418635)
  ref_set:add_pure_reference("baseEF/pakhairs16", 821022516)
  ref_set:add_pure_reference("baseEF/weapons_ef_marksman_crosshairs", 72583282)
  ref_set:add_pure_reference("baseEF/xhair_by_sniper", -2138946792)
  ref_set:add_pure_reference("baseEF/xhair_by_sniper_add_on", 1159103271)
  ref_set:add_pure_reference("baseEF/xhairs", 660617960)
  ref_set:add_pure_reference("baseEF/xhairsdn", 1689283570)
end

---------------------------------------------------------------------------------------
function addons.add_scope_mods(ref_set)
  ref_set:add_pure_reference("baseEF/zzzzsocom2-standardscope", 88479114)
  ref_set:add_pure_reference("baseEF/zzzzsocom2-thermalscope", 1051152180)
end

---------------------------------------------------------------------------------------
function addons.add_hd_hud_mod(ref_set)
  ref_set:add_pure_reference("baseEF/zzz_hd_mod", 774585927)
end

---------------------------------------------------------------------------------------
function addons.add_spark_sound_mod(ref_set)
  ref_set:add_pure_reference("baseEF/zzz_sparksound", -1569358164)
end

---------------------------------------------------------------------------------------
function addons.add_models(ref_set)
  ref_set:add_pure_reference("baseEF/11_tossizeaddon", 458341226)
  ref_set:add_pure_reference("baseEF/11_s_map3", -1052670052)
  ref_set:add_pure_reference("baseEF/11_picardpak", -239056152)
  ref_set:add_pure_reference("baseEF/10_zzznudekirk", 1473760401)
  ref_set:add_pure_reference("baseEF/10_ztosalienspt2", 2114876056)
  ref_set:add_pure_reference("baseEF/10_ztngtapestry", 957757313)
  ref_set:add_pure_reference("baseEF/10_znx01crew", -1341845841)
  ref_set:add_pure_reference("baseEF/10_zdukebabes", -928232224)
  ref_set:add_pure_reference("baseEF/10_zds9", -1102387530)
  ref_set:add_pure_reference("baseEF/10_warbot", -653263007)
  ref_set:add_pure_reference("baseEF/10_tron_mdl", 1700359384)
  ref_set:add_pure_reference("baseEF/10_tosvillains", 916138728)
  ref_set:add_pure_reference("baseEF/10_tosuniformpak", 1528853679)
  ref_set:add_pure_reference("baseEF/10_tosgeneric_crewmen", -293465367)
  ref_set:add_pure_reference("baseEF/10_tosdecker", -911934107)
  ref_set:add_pure_reference("baseEF/10_toscrew", 1283469609)
  ref_set:add_pure_reference("baseEF/10_tosalienspt1", 1646149603)
  ref_set:add_pure_reference("baseEF/10_tngskants", 585311328)
  ref_set:add_pure_reference("baseEF/10_tngcrew", -2130415835)
  ref_set:add_pure_reference("baseEF/10_tinman_mdl2", -1446533847)
  ref_set:add_pure_reference("baseEF/10_sw-battledroid", 1463942207)
  ref_set:add_pure_reference("baseEF/10_sonicdominion", -77133770)
  ref_set:add_pure_reference("baseEF/10_skunkymdl", -1345563103)
  ref_set:add_pure_reference("baseEF/10_sg_sg1", 112066663)
  ref_set:add_pure_reference("baseEF/10_sevenx", 858287488)
  ref_set:add_pure_reference("baseEF/10_sevenbikinix", 1499964935)
  ref_set:add_pure_reference("baseEF/10_seven", -1184989351)
  ref_set:add_pure_reference("baseEF/10_seska", -998768225)
  ref_set:add_pure_reference("baseEF/10_santa", 682599476)
  ref_set:add_pure_reference("baseEF/10_saavik_valeris", 1320893448)
  ref_set:add_pure_reference("baseEF/10_ronald", 1366176565)
  ref_set:add_pure_reference("baseEF/10_roms", -732857719)
  ref_set:add_pure_reference("baseEF/10_q3_ef_playermodels", -621258107)
  ref_set:add_pure_reference("baseEF/10_q", -1512277828)
  ref_set:add_pure_reference("baseEF/10_optimus", -409647394)
  ref_set:add_pure_reference("baseEF/10_nx01mirror", 226090764)
  ref_set:add_pure_reference("baseEF/10_nolfts", 98543238)
  ref_set:add_pure_reference("baseEF/10_nolf", -219698642)
  ref_set:add_pure_reference("baseEF/10_newfrontier", -1311780653)
  ref_set:add_pure_reference("baseEF/10_mress", 1442663415)
  ref_set:add_pure_reference("baseEF/10_mirrormress", -1924232075)
  ref_set:add_pure_reference("baseEF/10_md3_neo", 842295368)
  ref_set:add_pure_reference("baseEF/10_md3-dalekmk4", 2003440270)
  ref_set:add_pure_reference("baseEF/10_macpak", -1129624039)
  ref_set:add_pure_reference("baseEF/10_klingons", 1170602369)
  ref_set:add_pure_reference("baseEF/10_klingonhonor", 230290946)
  ref_set:add_pure_reference("baseEF/10_killing_game", -2049003024)
  ref_set:add_pure_reference("baseEF/10_kes", -1957866386)
  ref_set:add_pure_reference("baseEF/10_k7onlinepak1", 107985219)
  ref_set:add_pure_reference("baseEF/10_janewaypak", -2054389252)
  ref_set:add_pure_reference("baseEF/10_imps", -521103077)
  ref_set:add_pure_reference("baseEF/10_icheb", 1859368295)
  ref_set:add_pure_reference("baseEF/10_hazreg", -446168411)
  ref_set:add_pure_reference("baseEF/10_halo_masterchief_mdl", 1248116485)
  ref_set:add_pure_reference("baseEF/10_ferengi", 1457068367)
  ref_set:add_pure_reference("baseEF/10_fed", -1895118026)
  ref_set:add_pure_reference("baseEF/10_etherian", -1603561998)
  ref_set:add_pure_reference("baseEF/10_ent3_t&t", 1524921938)
  ref_set:add_pure_reference("baseEF/10_efteamrocket", -1066053278)
  ref_set:add_pure_reference("baseEF/10_efspmarine40k", -507208778)
  ref_set:add_pure_reference("baseEF/10_efmdl_taz", -1190733161)
  ref_set:add_pure_reference("baseEF/10_efmdl_fang", 1491700833)
  ref_set:add_pure_reference("baseEF/10_efmdl_dalek2005", 361798512)
  ref_set:add_pure_reference("baseEF/10_efmdl_cleanerwolf", 258137326)
  ref_set:add_pure_reference("baseEF/10_efmdl_assimilatrix", 442754269)
  ref_set:add_pure_reference("baseEF/10_efmdl-vader", 115235738)
  ref_set:add_pure_reference("baseEF/10_efmdl-tmnt", 1159815924)
  ref_set:add_pure_reference("baseEF/10_efmdl-t-101", -1102825205)
  ref_set:add_pure_reference("baseEF/10_efmdl-stormtrooper", -2068529703)
  ref_set:add_pure_reference("baseEF/10_efmdl-spanky", -1990759005)
  ref_set:add_pure_reference("baseEF/10_efmdl-sonic", -756802123)
  ref_set:add_pure_reference("baseEF/10_efmdl-snoopy", 489504233)
  ref_set:add_pure_reference("baseEF/10_efmdl-samus", 970886589)
  ref_set:add_pure_reference("baseEF/10_efmdl-robocop", 1237842096)
  ref_set:add_pure_reference("baseEF/10_efmdl-r2d2", -1963687114)
  ref_set:add_pure_reference("baseEF/10_efmdl-padman", -170394912)
  ref_set:add_pure_reference("baseEF/10_efmdl-onilink", 19998771)
  ref_set:add_pure_reference("baseEF/10_efmdl-mrbunny", 736297970)
  ref_set:add_pure_reference("baseEF/10_efmdl-megabyte", -1162264691)
  ref_set:add_pure_reference("baseEF/10_efmdl-maximus", -1176224062)
  ref_set:add_pure_reference("baseEF/10_efmdl-massacre", -12500946)
  ref_set:add_pure_reference("baseEF/10_efmdl-marvin", -1329536974)
  ref_set:add_pure_reference("baseEF/10_efmdl-magneto", 1515048375)
  ref_set:add_pure_reference("baseEF/10_efmdl-laracroft", -596156980)
  ref_set:add_pure_reference("baseEF/10_efmdl-jarjar", -590254586)
  ref_set:add_pure_reference("baseEF/10_efmdl-homer3d", 866142731)
  ref_set:add_pure_reference("baseEF/10_efmdl-efpkoolkat", 1749403327)
  ref_set:add_pure_reference("baseEF/10_efmdl-dangergirl", -539787756)
  ref_set:add_pure_reference("baseEF/10_efmdl-bobafett", -1309946112)
  ref_set:add_pure_reference("baseEF/10_efmdl-bender", -811057160)
  ref_set:add_pure_reference("baseEF/10_efmdl-batman", 174233742)
  ref_set:add_pure_reference("baseEF/10_efmdl-animal", 2027478)
  ref_set:add_pure_reference("baseEF/10_efmdl-alien3", 299427683)
  ref_set:add_pure_reference("baseEF/10_efmdl-abe", 605305936)
  ref_set:add_pure_reference("baseEF/10_efmd3-kulhane", 986884168)
  ref_set:add_pure_reference("baseEF/10_efmd3-grimdemon", 437615973)
  ref_set:add_pure_reference("baseEF/10_efjohnny5", 2144103046)
  ref_set:add_pure_reference("baseEF/10_efgrinch", 569171994)
  ref_set:add_pure_reference("baseEF/10_efconni", 1985114405)
  ref_set:add_pure_reference("baseEF/10_efbravo_soundfix", -1730817046)
  ref_set:add_pure_reference("baseEF/10_ef_droideka", -1192641121)
  ref_set:add_pure_reference("baseEF/10_dukepak", 1336786449)
  ref_set:add_pure_reference("baseEF/10_drive", 897481779)
  ref_set:add_pure_reference("baseEF/10_doctor", 1473549864)
  ref_set:add_pure_reference("baseEF/10_deltaboys", 1826287974)
  ref_set:add_pure_reference("baseEF/10_darthmaul", -1958839763)
  ref_set:add_pure_reference("baseEF/10_csatlostng", 158295493)
  ref_set:add_pure_reference("baseEF/10_constellation", 2430252)
  ref_set:add_pure_reference("baseEF/10_christmassonic", 833765593)
  ref_set:add_pure_reference("baseEF/10_celes", -1449077412)
  ref_set:add_pure_reference("baseEF/10_captain_ransom", -282621336)
  ref_set:add_pure_reference("baseEF/10_bond", -426771119)
  ref_set:add_pure_reference("baseEF/10_bajorans", -1281641407)
  ref_set:add_pure_reference("baseEF/10_andorians2", 2114768979)
  ref_set:add_pure_reference("baseEF/10_andorians", 2054587157)
  ref_set:add_pure_reference("baseEF/10_alien", 1383744283)
  ref_set:add_pure_reference("baseEF/09_zbestofbothworlds", 1400496228)
  ref_set:add_pure_reference("baseEF/09_tospak2", -1570098188)
  ref_set:add_pure_reference("baseEF/09_tngcrew_var1", -1095863766)
  ref_set:add_pure_reference("baseEF/09_sonicthehedgehog", -1840460835)
  ref_set:add_pure_reference("baseEF/09_klingons_alt1", -1401219183)
  ref_set:add_pure_reference("baseEF/09_efmdl-batman_alt1", 1397821752)
  ref_set:add_pure_reference("baseEF/09_efbravo", -639020603)
  ref_set:add_pure_reference("baseEF/09_crewmen", -1319785711)
  ref_set:add_pure_reference("baseEF/08_zzzzzztnggold", 1395343593)
  ref_set:add_pure_reference("baseEF/08_tngcrew_var2", 188563959)
  ref_set:add_pure_reference("baseEF/08_sonicthehedgehog_alt1", 384285045)
  ref_set:add_pure_reference("baseEF/08_mirror", -225682309)
  ref_set:add_pure_reference("baseEF/07_zzztngcrew", 1193508968)
  ref_set:add_pure_reference("baseEF/07_borg-skins_trekmaster", -1345076650)
  ref_set:add_pure_reference("baseEF/06_data", -249949097)
  ref_set:add_pure_reference("baseEF/00_zzzproton", -1022567409)
end

return addons
