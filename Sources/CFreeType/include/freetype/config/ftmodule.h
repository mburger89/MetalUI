/*
 * MetalUI (ruling FT-A): only the drivers MetalUIFreeType uses — TrueType and
 * CFF outlines, their shared SFNT/PostScript support, and the grayscale
 * renderer. Replaces FreeType's generated default list; see VENDORED.md.
 */
FT_USE_MODULE( FT_Driver_ClassRec, tt_driver_class )
FT_USE_MODULE( FT_Driver_ClassRec, cff_driver_class )
FT_USE_MODULE( FT_Module_Class, psaux_module_class )
FT_USE_MODULE( FT_Module_Class, psnames_module_class )
FT_USE_MODULE( FT_Module_Class, sfnt_module_class )
FT_USE_MODULE( FT_Renderer_Class, ft_smooth_renderer_class )

/* EOF */
