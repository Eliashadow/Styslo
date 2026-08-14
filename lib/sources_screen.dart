// A screem that allows to manage sources

// ====  Essential imports ==== 
import 'package:flutter/material.dart';
import 'dart:convert';

// ====  Network imports ==== 
import 'package:http/http.dart' as http;

// ====  Log imports ==== 
import 'package:logger/logger.dart';

// ====  Other screens imports ==== 

import 'local_database.dart';
//  Returning data to main
class SourcesScreen extends StatefulWidget {

  // ====  Network ==== 
  final bool initialStatus;

  // Requesting status from main 
  const SourcesScreen({
    super.key,
    
    required this.initialStatus,

    });

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

// Sources Screen
class _SourcesScreenState extends State<SourcesScreen> {
  // ====  Categories ==== 
  List<dynamic> _categoriesWithSources = [];

  // ====  Network ==== 
  bool _isLoading = true;
  late bool _isOnline;
  final String _baseUrl = "http://192.168.1.126:8000/api"; 
  
  // ====  Writing ==== 
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _sourceNameController = TextEditingController();
  final TextEditingController _sourceUrlController = TextEditingController();

  // Logs
  final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,       
    errorMethodCount: 5,  
    lineLength: 80,       
      ),
    );

  // Initializating sources
  @override
  void initState() {
    super.initState();

    _isOnline = widget.initialStatus;

    _fetchSources();
  }

  // Getiing sources from DB or local
  Future<void> _fetchSources() async {
    // Checking if there is connection
    if (_isOnline) {
      setState(() => _isLoading = true);
      try {
        final response = await http.get(Uri.parse("$_baseUrl/sources"));
        if (response.statusCode == 200) {
          setState(() {
            _categoriesWithSources = json.decode(utf8.decode(response.bodyBytes));
            _isLoading = false;
          });
        }
      } catch (e) {
        logger.e("[SOURCES SCREEN] Error loading: $e");
        
        if (!mounted) return;

        setState(() => _isLoading = false);
      }
    } else {
      // If not trying get categories with sources from local
      try {
        final localData = await LocalDatabase.instance.getCategoriesWithSources();
        setState(() {
          _categoriesWithSources = localData;
          _isLoading = false;
        });
        logger.i("[SOURCES SCREEN] Loaded categories and sources from local DB.");
      } catch (e) {
        logger.e("[SOURCES SCREEN] Error loading offline sources: $e");
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _addCategory(String name) async {
    if (name.isEmpty) return;
    // Online mode
    if (_isOnline) {
      try {
        final response = await http.post(
          Uri.parse("$_baseUrl/categories"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"name": name}),
        );
        if (!mounted) return;

        if (response.statusCode == 201) {
          _categoryController.clear();
          _fetchSources();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Category '$name' created")),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create category: ${response.statusCode}'))
          );
        }
      } catch (e) {
        if (!mounted) return;

        logger.e("[SOURCES SCREEN] Error creating category: $e");
      }
    // Offline mode
    } else {
      try {
        await LocalDatabase.instance.addCategory(name);
        
        _categoryController.clear();
        _fetchSources();

        if (!mounted) return;

         ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Category '$name' created")),
          );
       } catch(e) {
        logger.e("[SOURCES SCREEN] Error adding source: $e");
       }
    }
  }

  Future<void> _addSourceToCategory(String catName, String srcName, String srcUrl) async {
    if (srcName.isEmpty || srcUrl.isEmpty) return;

    // Online mode
    if(_isOnline) {
      try {
        final response = await http.post(
          Uri.parse("$_baseUrl/sources"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "name": srcName,
            "url": srcUrl,
            "category": catName,
          }),
        );
        if (!mounted) return;

        if (response.statusCode == 201 || response.statusCode == 200) {
          _sourceNameController.clear();
          _sourceUrlController.clear();
          _fetchSources(); 
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Source added to category $catName")),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add source to category ${response.statusCode}'))
          );
        }
      } catch (e) {
        if (!mounted) return;

        logger.e("[SOURCES SCREEN] Error adding source: $e");
      }

    // Offline mode
    } else {
      try {
        await LocalDatabase.instance.addSource(srcName, catName, srcUrl);

        _sourceNameController.clear();
        _sourceUrlController.clear();
        _fetchSources();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Source created locally")),
          );
      } catch(e) {
        logger.e("[SOURCES SCREEN] Error offline adding source: $e");
      }
    }
  }

  Future<void> _deleteCategory(String catName) async {
    if (_isOnline) {
      // Online mode 
      try {
        final response = await http.delete(Uri.parse("$_baseUrl/categories/$catName"));
        if (!mounted) return;

        if (response.statusCode == 200) {
          _fetchSources();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Category '$catName' deleted")),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete categoty ${response.statusCode}'))
          );
        }
      } catch (e) {
        if (!mounted) return;
        logger.e("[SOURCES SCREEN] Error deleting category: $e");
      }
    } else {
      // Offline mode 
      try {
        await LocalDatabase.instance.deleteCategory(catName);

        _fetchSources();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Category '$catName' deleted locally")),
        );
      } catch(e) {
        logger.e('[SOURCE SCREEN] Error deleting category in offline mode: $e');
      }
    }
  }

  Future<void> _deleteSource(int id) async {
    if (_isOnline) {
      // Online mode
      try {
        final response = await http.delete(Uri.parse("$_baseUrl/sources/$id"));
        if (!mounted) return;

        if (response.statusCode == 200) {
          _fetchSources();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Source deleted")),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete source ${response.statusCode}'))
          );
        }
      } catch (e) {
        if (!mounted) return;
        logger.e("[SOURCES SCREEN] Error deleting source: $e");
      }
    } else {
      // Offline mode
        try {
          LocalDatabase.instance.deleteSource(id);
          _fetchSources();

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Source deleted locally")),
          );
        } catch(e) {
          logger.e('[SOURCE SCREEN] Error deleting source in offline mode: $e');
        }
    }
  }

  // Ui for inputing category name
  void _showAddCategoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("New category"),
        content: TextField(
          controller: _categoryController,
          decoration: const InputDecoration(hintText: "Name (e.g., Sports ⚽)"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              _addCategory(_categoryController.text);
              Navigator.pop(context);
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }
  // Ui for inputing source data
  void _showAddSourceDialog(String catName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Add source to $catName"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _sourceNameController,
              decoration: const InputDecoration(hintText: "Name (e.g., TSN)"),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _sourceUrlController,
              decoration: const InputDecoration(hintText: "RSS URL link"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              _addSourceToCategory(catName, _sourceNameController.text, _sourceUrlController.text);
              Navigator.pop(context);
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  // UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
         
        title: const Text("My sources"),
        actions: [    
          IconButton(
            icon: const Icon(Icons.add_box, color: Colors.greenAccent),
            tooltip: "Create category",
            onPressed: _showAddCategoryDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchSources,
          )
        ],
      ),
      body: Column(
        children: [
          // Offline Banner
          if (!_isOnline)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16), 
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.offline_bolt, color: Colors.redAccent, size: 20),
                  SizedBox(width: 8),
                  Text(
                    "You're offline. Check your connection",
                    style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          Expanded(
              child: _isLoading && _isOnline
                  ? const Center(child: CircularProgressIndicator())
                  : _categoriesWithSources.isEmpty
                      ? const Center(child: Text("Database is empty"))
                      : ListView.builder(
                          itemCount: _categoriesWithSources.length,
                          itemBuilder: (context, index) {
                            final category = _categoriesWithSources[index];
                            final String catName = category["category_name"];
                            final List<dynamic> sources = category["sources"];

                            return Card(
                              margin: const EdgeInsets.all(10),
                              elevation: 3,
                              child: ExpansionTile(
                                initiallyExpanded: true,
                                title: Text(
                                  catName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                ),
                                subtitle: Text("Sources: ${sources.length}"),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                        icon: const Icon(Icons.add_circle_outline, color: Colors.blueAccent),
                                        tooltip: "Add RSS source to this category",
                                        onPressed: () => _showAddSourceDialog(catName),
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_forever, color: Colors.deepOrange),
                                      tooltip: "Delete category with all sources",
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text("Delete category?"),
                                            content: Text("This will delete the category '$catName' and all its sources."),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(context), child: const Text("No")),
                                              TextButton(
                                                onPressed: () {
                                                  _deleteCategory(catName);
                                                  Navigator.pop(context);
                                                },
                                                child: const Text("Yes, delete", style: TextStyle(color: Colors.red)),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                    const Icon(Icons.expand_more),
                                  ],
                                ),
                                children: sources.map<Widget>((src) {
                                  return ListTile(
                                    leading: const Icon(Icons.language, color: Colors.blue),
                                    title: Text(src["name"]),
                                    subtitle: Text(src["url"], maxLines: 1, overflow: TextOverflow.ellipsis),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete),
                                      color: Colors.red,
                                      onPressed: () => _deleteSource(src["id"]),
                                    ),
                                  );
                                }).toList(),
                              ),
                            );
                          },
                        ),
          ),
        ]
      )
    );
  } // UI
}