"""
Used to determine which additional pk3s are required by a map for client download purposes.
"""

import re
import os
import typing
import abc
from . import game_parse
from . import misc

shader_file_reg = re.compile(r"scripts/([^/]*)\.shader", flags=re.IGNORECASE)
def is_shader_file_path(path:str):
    return shader_file_reg.fullmatch(path) != None

class SourcePriority():
    def __init__(self, category:int, position:int):
        self.category = category
        self.position = position

    def sort_key(self, isShader:bool):
        return (-self.category, 0 if isShader else 1, self.position)

class SourceList():
    """ List of potential asset sources for dependency resolution. All sources must be pre-indexed
    in the provided asset index. """
    def __init__(self, asset_index:"AssetIndex"):
        self.asset_index = asset_index
        self.priority_table : dict[str, SourcePriority] = {}

    def add_source(self, source:str, category:int=0):
        assert source in self.asset_index.registered_sources
        if source in self.priority_table:
            assert self.priority_table[source].category >= category
        else:
            self.priority_table[source] = SourcePriority(category, len(self.priority_table))

class Asset(abc.ABC):
    """ An asset represents something like a shader, image, model, or sound that can satisfy a dependency.
    Assets can have their own subdependencies, which are retrieved by the get_subdependencies method. """
    source = ""

    def get_subdependencies(self) -> typing.Iterable["Dependency"]:
        return ()

    @abc.abstractmethod
    def get_sort_key(self, sourcePriority:SourcePriority) -> typing.Any:
        pass

    @abc.abstractmethod
    def equivalent(self, other:"Asset"):
        pass

class ShaderAsset(Asset):
    asset_type = "shader"
    def __init__(self, source:str, name:str, file_info:dict, text:str):
        self.source = source
        self.name = name
        self.text = text
        self.source_file_name = file_info["filename"]

    def get_sort_key(self, source_priority:SourcePriority):
        return source_priority.sort_key(True)

    def equivalent(self, other:Asset):
        return type(self) == type(other) and self.text == other.text    #type: ignore

    def get_subdependencies(self) -> typing.Iterable["Dependency"]:
        deps = game_parse.ShaderDependencies(self.text)
        for image in deps.images:
            yield ImageDependency(image)
        for image in deps.images_optional:
            yield ImageDependency(image, optional=True)
        for video in deps.videos:
            if not ("/" in video or "\\" in video):
                # for consistency with CIN_PlayCinematic
                video = "video/" + video
            yield VideoDependency(video)

    def __repr__(self):
        return f"shaderasset|{self.source}:{self.source_file_name}:{self.name}"

class FileAsset(Asset):
    asset_type = "unknown"

    def __init__(self, source:str, info:dict):
        self.source = source
        self.name : str = info["filename"]
        self.ext : str = info["filename"].rsplit('.', 1)[1].lower()
        self.filesize : int = int(info["filesize"])

    def get_sort_key(self, sourcePriority:SourcePriority):
        return sourcePriority.sort_key(False)

    def equivalent(self, other:Asset):
        return type(self) == type(other) and self.filesize == other.filesize    #type: ignore

    def __repr__(self):
        return f"{self.asset_type}asset|{self.source}:{self.name}"

class ImageAsset(FileAsset):
    asset_type = "image"

class SoundAsset(FileAsset):
    asset_type = "sound"

class VideoAsset(FileAsset):
    asset_type = "video"

class Md3Asset(FileAsset):
    asset_type = "md3"
    def __init__(self, source:str, info:dict):
        super().__init__(source, info)
        self.shader_dependencies : set[str] = set(info["md3info"]["shaders"])

    def get_subdependencies(self) -> typing.Iterable["Dependency"]:
        for shader_name in self.shader_dependencies:
            yield ShaderDependency(shader_name)

class Dependency(abc.ABC):
    """ Represents a certain resource requirement that can be fulfilled by an asset. """
    dependency_type = "unknown"

    def __init__(self, name:str, optional=False):
        self.name = misc.strip_ext(name).lower()
        self.optional = optional

    def __eq__(self, other:"Dependency"):
        return self.dependency_type == other.dependency_type and self.name == other.name

    def __repr__(self):
        return f"{self.dependency_type}dep{'_optional' if self.optional else ''}|{self.name}"

    def __hash__(self):
        return f"{self.dependency_type}:{self.name}".__hash__()

    @abc.abstractmethod
    def get_assets(self, assetIndex:"AssetIndex") -> typing.Iterable["Asset"]:
        pass

class ShaderDependency(Dependency):
    dependency_type = "shader"
    def get_assets(self, asset_index:"AssetIndex") -> typing.Iterable["Asset"]:
        return (asset for asset in asset_index.asset_table.get(self.name, ()) if isinstance(asset, ImageAsset) or isinstance(asset, ShaderAsset))

class ImageDependency(Dependency):
    dependency_type = "image"
    def get_assets(self, asset_index:"AssetIndex") -> typing.Iterable["Asset"]:
        return (asset for asset in asset_index.asset_table.get(self.name, ()) if isinstance(asset, ImageAsset))

class SoundDependency(Dependency):
    dependency_type = "sound"
    def get_assets(self, asset_index:"AssetIndex") -> typing.Iterable["Asset"]:
        return (asset for asset in asset_index.asset_table.get(self.name, ()) if isinstance(asset, SoundAsset))

class ModelDependency(Dependency):
    dependency_type = "model"
    def get_assets(self, asset_index:"AssetIndex") -> typing.Iterable["Asset"]:
        return (asset for asset in asset_index.asset_table.get(self.name, ()) if isinstance(asset, Md3Asset))

class VideoDependency(Dependency):
    dependency_type = "video"
    def get_assets(self, asset_index:"AssetIndex") -> typing.Iterable["Asset"]:
        return (asset for asset in asset_index.asset_table.get(self.name, ()) if isinstance(asset, VideoAsset))

def assets_from_pk3(source:str, info:dict):
    output : dict[str, list[Asset]] = {}

    for subfile in info["pk3_subfiles"]:
        split = subfile["filename"].rsplit('.', 1)
        if len(split) < 2:
            continue
        baseName = split[0].lower()
        ext = split[1].lower()

        if ext in ("tga", "jpg"):
            asset = ImageAsset(source, subfile)
            output.setdefault(baseName, []).append(asset)

        if ext in ("wav", "mp3", "ogg"):
            asset = SoundAsset(source, subfile)
            output.setdefault(baseName, []).append(asset)

        if ext in ("md3"):
            asset = Md3Asset(source, subfile)
            output.setdefault(baseName, []).append(asset)
                
        if ext in ("roq"):
            asset = VideoAsset(source, subfile)
            output.setdefault(baseName, []).append(asset)

        if is_shader_file_path(subfile["filename"]):
            for name, shader in subfile.get("shaders", {}).items():
                asset = ShaderAsset(source, name, subfile, shader["text"])
                output.setdefault(name, []).append(asset)

    return output

class AssetIndex():
    """ Cache of data from potential sources, used when creating SourceList. """
    def __init__(self):
        self.asset_table : dict[str, list[Asset]] = {}
        self.registered_sources : set[str] = set()

    def asset_counts_str(self) -> str:
        """ Returns a readable string representation of the number of each type of asset. """
        asset_counts = {}
        for asset_list in self.asset_table.values():
            for asset in asset_list:
                asset_counts[asset.asset_type] = asset_counts.get(asset.asset_type, 0) + 1
        return ", ".join([f"{asset_type.capitalize()}: {count}" for asset_type, count in asset_counts.items()])

    def register_assets(self, source:str, assets:dict[str, list[Asset]]):
        assert source not in self.registered_sources
        self.registered_sources.add(source)
        for baseName, asset_list in assets.items():
            self.asset_table.setdefault(baseName, []).extend(asset_list)

    def register_pk3(self, source:str, info:dict):
        self.register_assets(source, assets_from_pk3(source, info))

class DependencySatisfiers():
    """ Generates set of assets that satisfy a given dependency. """
    def __init__(self, dependency:Dependency, source_list:SourceList):
        def get_sort_key(asset:Asset):
            source_priority = source_list.priority_table[asset.source]
            return asset.get_sort_key(source_priority)

        # Get list of assets from the source list that satisfy dependency.
        self.assets = [asset for asset in dependency.get_assets(source_list.asset_index)
                        if asset.source in source_list.priority_table]
        self.assets.sort(key=get_sort_key)

        # Get list of assets with only elements equivalent to the highest precedence match included.
        self.equivalent_assets = [] if len(self.assets) == 0 else \
                        [self.assets[0], *(x for x in self.assets[1:] if x.equivalent(self.assets[0]))]

class DependencyPool():
    """ Represents a list of dependencies for a map. """
    def __init__(self):
        # Map of dependencies to a set of descriptions describing the source.
        self.dependencies : dict[Dependency, set[str]] = {}
        self.warnings : set[str] = set()

    def add_dependency(self, dependency:Dependency, description:str):
        """ Adds dependency to pool. """
        self.dependencies.setdefault(dependency, set()).add(description)

    def add_bsp_dependencies(self, bsp_info:dict):
        """ Add dependencies from bsp. """
        for shadername in bsp_info["shaders"]:
            self.add_dependency(ShaderDependency(shadername), "bspshaders")

        entities = game_parse.Entities()
        entities.import_serializable(bsp_info["entities"])
        entdep = game_parse.EntityDependencies(entities)
        self.warnings.update(entdep.errors)
        for sound_name in entdep.sounds:
            self.add_dependency(SoundDependency(sound_name), "entities")
        for model_name in entdep.models:
            self.add_dependency(ModelDependency(model_name), "entities")

class DependencyResult():
    """ Represents a set of equivalent assets that satisfy a dependency, as well
    as a set of descriptions of the origin of the dependency. """
    def __init__(self):
        self.assets : set[Asset] = set()
        self.descriptions : set[str] = set()
    
    def sources(self):
        # Returns set of sources (e.g. pk3s) that can satisfy the dependency.
        return {asset.source for asset in self.assets}

ResolvedDependencies = dict[Dependency, DependencyResult]

def resolve_dependencies(depdendency_pool:DependencyPool, source_list:SourceList) -> ResolvedDependencies:
    """ Resolves dependencies and their subdependencies to assets that satisfy them. """
    result = ResolvedDependencies()

    def resolve(dependency:Dependency, descriptions:set[str]):
        entry = result.setdefault(dependency, DependencyResult())
        entry.descriptions.update(descriptions)

        sat = DependencySatisfiers(dependency, source_list)
        for asset in sat.equivalent_assets:
            entry.assets.add(asset)

        if len(sat.equivalent_assets) > 0:
            for subDependency in sat.equivalent_assets[0].get_subdependencies():
                subDescriptions = {f"{description}=>{sat.assets[0]}" for description in descriptions}
                resolve(subDependency, subDescriptions)

    for dependency, descriptions in depdendency_pool.dependencies.items():
        resolve(dependency, descriptions)

    return result

MinimumSources = list[str]

def get_minimum_sources(res:ResolvedDependencies, source_list:SourceList) -> MinimumSources:
    """ Determines minimum set of sources to satisfy all dependencies. """

    # Obtain list of all potential sources sorted from lowest to highest priority.
    source_set : set[str] = set()
    for entry in res.values():
        source_set.update(entry.sources())
    def get_sort_key(source:str):
        return source_list.priority_table[source].sort_key(False)
    sources_sorted = sorted(source_set, key=get_sort_key, reverse=True)

    # Working set of dependencies mapped to sources (pk3s) that satisfy them.
    # Sources will be removed as they are determined to be redundant.
    current_resolves : dict[Dependency, set[str]] = {}
    for dependency, entry in res.items():
        current_resolves[dependency] = set()
        for source in entry.sources():
            current_resolves[dependency].add(source)

    def source_needed_by(source:str) -> set[Dependency]:
        """ Returns set of dependencies that are only satisfied by this source. """
        result : set[Dependency] = set()
        for dependency, sources in current_resolves.items():
            if len(sources) == 1 and source in sources:
                result.add(dependency)
        return result

    def remove_source(source:str):
        for sources in current_resolves.values():
            sources.discard(source)

    # Iterate sources from highest to lowest priority, deleting redundant ones.
    needed : list[str] = []
    for source in sources_sorted:
        needed_by = source_needed_by(source)
        if len(needed_by) > 0:
            needed.append(source)
        else:
            remove_source(source)

    needed.reverse()
    return needed

def get_unsatisfied(res:ResolvedDependencies, optional:bool) -> ResolvedDependencies:
    """ Filter depdendencies to include only unresolved ones. """
    return {dependency: entry for dependency, entry in res.items() if len(entry.sources()) == 0 and optional == dependency.optional}

def log_dependencies(res:ResolvedDependencies, ms:MinimumSources, logger:misc.Logger):
    unsatisfied = get_unsatisfied(res, False)
    unsatisfied_optional = get_unsatisfied(res, True)

    logger.log_info( f"needed sources: {' '.join(ms)}" )
    logger.log_info( f"unresolved: {len(unsatisfied)}" )
    logger.log_info( f"unresolved optional: {len(unsatisfied_optional)}" )
    logger.log_info( "" )

    for dependency in {**unsatisfied, **unsatisfied_optional}:
        logger.log_info(f"unresolved dependency: {dependency}")
        for ref in res[dependency].descriptions:
            logger.log_info(f"  referenced by: {ref}")
    if len(unsatisfied) > 0:
        logger.log_info( "" )

    # map of sources to dependencies satisfied
    source_index : dict[str, set[Dependency]] = {}
    for dependency, dep_result in res.items():
        for source in dep_result.sources():
            source_index.setdefault(source, set()).add(dependency)

    for source in ms:
        logger.log_info(f"source: {source}")
        for dependency in source_index[source]:
            logger.log_info(f"  satisfies dependency: {dependency}")
            for asset in res[dependency].assets:
                if asset.source == source:
                    logger.log_info(f"    with: {asset}")
            for ref in res[dependency].descriptions:
                logger.log_info(f"    referenced by: {ref}")
